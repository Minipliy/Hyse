#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
views = TrainingViewSources.read
sheet = views[/private func communityPostActionsSheet.*?private func communityPostActionRow/m] || ""

abort("community reactions still use the wrapping native context menu") if views.include?(".controlGroupStyle(.compactMenu)")
abort("long press no longer opens message actions") unless views.include?(".onLongPressGesture(minimumDuration: 0.35)")
abort("reaction choices are not in one horizontal stack") unless sheet.include?("HStack(spacing: 0)") && sheet.include?("ForEach(reactionChoices")
abort("reaction buttons are not evenly distributed") unless sheet.include?(".frame(maxWidth: .infinity)")
abort("all six reactions are not configured") unless views.include?('["👍", "❤️", "🔥", "👏", "💪", "😂"]')

puts "community reaction row checks passed"
