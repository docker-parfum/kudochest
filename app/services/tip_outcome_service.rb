# frozen_string_literal: true

# Given a set of Tips, which are assumed to be recently created:
#  * Update each recipient profile's points/jabs received and received timestamp
#  * Update the sender profile points/jabs sent and sent timestamp
#  * Update the team's points/jabs sent

class TipOutcomeService < Base::Service
  option :tips
  option :destroy, default: -> { false }

  def call
    return if tips.blank?

    Tip.transaction do
      update_to_profiles
      update_from_profile
      update_team
      tips.map(&:destroy) if destroy
    end

    refresh_leaderboards
  end

  private

  # rubocop:disable Metrics/AbcSize
  def update_to_profiles
    tips.each do |tip|
      profile = tip.to_profile
      profile.with_lock do
        last_tip_received_at = destroy ? previous_received_at(profile) : tip.created_at
        value_col = tip.jab? ? :jabs_received : :points_received
        value = profile.send(value_col).send(operator, tip.quantity.abs)
        balance = profile.balance.send(operator, tip.quantity)
        profile.update!(value_col => value, balance:, last_tip_received_at:)
      end
    end
  end

  def update_from_profile
    from_profile.with_lock do
      points_sent = from_profile.points_sent.send(operator, total_points)
      jabs_sent = from_profile.jabs_sent.send(operator, total_jabs)
      last_tip_sent_at = destroy ? previous_sent_at : tips.first.created_at
      from_profile.update!(points_sent:, jabs_sent:, last_tip_sent_at:)
    end
  end

  def update_team
    team.with_lock do
      points_sent = team.points_sent.send(operator, total_points)
      jabs_sent = team.jabs_sent.send(operator, total_jabs)
      balance = team.balance.send(operator, total_points - total_jabs)
      team.update!(points_sent:, jabs_sent:, balance:)
    end
  end
  # rubocop:enable Metrics/AbcSize

  def refresh_leaderboards
    LeaderboardRefreshWorker.perform_async(team.id)
    LeaderboardRefreshWorker.perform_async(team.id, true)
  end

  def previous_received_at(to_profile)
    Tip.where(to_profile:).order(created_at: :desc).first&.created_at
  end

  def previous_sent_at
    Tip.where(from_profile:).order(created_at: :desc).first&.created_at
  end

  def total_points
    @total_points ||= tips.reject(&:jab?).sum(&:quantity)
  end

  def total_jabs
    @total_jabs ||= tips.select(&:jab?).sum(&:quantity).abs
  end

  def team
    @team ||= tips.first.team
  end

  def from_profile
    @from_profile ||= tips.first.from_profile
  end

  def operator
    @operator ||= destroy ? '-' : '+'
  end
end
