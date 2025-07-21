#!/usr/bin/env ruby
# Script to reprocess existing replays with updated data structure fixes

require_relative 'config/environment'

puts "🔄 Reprocessing existing replays with updated data structure..."

replays = Replay.all
puts "Found #{replays.count} replays to reprocess"

replays.each_with_index do |replay, index|
  puts "\n#{index + 1}/#{replays.count}: Processing #{replay.filename}"
  
  begin
    # Force reprocessing
    replay.reprocess!
    puts "✅ Successfully reprocessed #{replay.filename}"
    
    # Check if game_info has data now
    game_info = replay.game_info
    if game_info && !game_info.empty?
      puts "   📊 Game info: #{game_info['champion_name']} - #{game_info['kills']}/#{game_info['deaths']}/#{game_info['assists']}"
    else
      puts "   ⚠️  Game info still empty"
    end
    
  rescue => e
    puts "❌ Error reprocessing #{replay.filename}: #{e.message}"
  end
end

puts "\n🎉 Reprocessing complete!"
