# frozen_string_literal: true
class Reports::TeamDigestService < Reports::BaseDigestService
  include PointsHelper

  option :team

  def call
    team_data
  end

  private

  def team_data
    OpenStruct.new(
      team: team,
      points_sent: points_sent,
      num_participants: num_participants,
      points_from_streak: points_from_streak,
      levelup_sentence: levelup_sentence,
      top_recipients: top_recipients,
      top_givers: top_givers,
      loot_claims_sentence: loot_claims_sentence
    )
  end

  def num_participants
    tips.map(&:to_profile).uniq.size + tips.map(&:from_profile).uniq.size
  end

  def recipient_quantities
    profiles.map do |profile|
      OpenStruct.new(profile: profile, quantity: quantity_to(profile))
    end
  end

  def giver_quantities
    profiles.map do |profile|
      OpenStruct.new(profile: profile, quantity: quantity_from(profile))
    end
  end

  def quantity_to(profile)
    tips.select { |tip| tip.to_profile_id == profile.id }.sum(&:quantity)
  end

  def quantity_from(profile)
    tips.select { |tip| tip.from_profile_id == profile.id }.sum(&:quantity)
  end

  def tips
    @tips ||=
      Tip.where(to_profile_id: profiles.map(&:id))
         .where('tips.created_at > ?', timeframe)
         .includes(:from_profile)
         .order(quantity: :desc)
  end

  def points_sent
    @points_sent ||= tips.sum(:quantity)
  end

  def points_from_streak
    tips.where(source: 'streak').sum(:quantity)
  end

  def levelup_sentence
    return unless team.enable_levels?
    return 'No users leveled up.' if num_levelups.zero?
    "#{pluralize(num_levelups, 'user')} leveled up."
  end

  def num_levelups
    @num_levelups ||= profile_levelups.count { |stat| stat.delta.positive? }
  end

  def profile_levelups
    profiles.map do |profile|
      previous_level =
        PointsToLevelService.call(
          team: team,
          points: profile.points - quantity_to(profile)
        )
      OpenStruct.new(name: profile.display_name, delta: profile.level - previous_level)
    end
  end

  def loot_claims_sentence
    return unless team.enable_loot?
    claims = Claim.where('created_at > ?', timeframe)
    return 'None' if claims.size.zero?
    num_pending = claims.all.count(&:pending?)
    "#{pluralize(claims.size, 'new claim')} (#{num_pending} pending fulfillment)"
  end

  def timeframe
    @timeframe ||= num_days.days.ago
  end

  def profiles
    @profiles ||= team.profiles.active
  end
end
