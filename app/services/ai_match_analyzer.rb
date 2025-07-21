class AiMatchAnalyzer
  def initialize(replay)
    @replay = replay
    @game_info = replay.game_info
    
    # Debug logging to see what data we're getting
    Rails.logger.info "AI Analyzer Debug - game_info keys: #{@game_info.keys.inspect}"
    Rails.logger.info "AI Analyzer Debug - game_info sample: #{@game_info.slice('champion_name', 'kills', 'deaths', 'assists', 'win').inspect}"
  end

  def generate_analysis
    begin
      Rails.logger.info "Starting AI analysis generation..."
      
      summary = generate_ai_summary
      Rails.logger.info "Generated summary: #{summary&.truncate(100)}"
      
      suggestions = generate_suggestions
      Rails.logger.info "Generated suggestions: #{suggestions&.length} items"
      
      timeline_events = generate_timeline_events
      Rails.logger.info "Generated timeline events: #{timeline_events&.length} items"
      
      win_probability = calculate_win_probability_timeline
      Rails.logger.info "Calculated win probability: #{win_probability}"
      
      performance_score = calculate_performance_score
      Rails.logger.info "Calculated performance score: #{performance_score}"
      
      result = {
        summary: summary,
        suggestions: suggestions,
        timeline_events: timeline_events,
        win_probability: win_probability,
        performance_score: performance_score
      }
      
      Rails.logger.info "AI Analysis completed successfully"
      result
    rescue => e
      Rails.logger.error "AI Analysis failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Return a fallback analysis
      {
        summary: "Analysis temporarily unavailable due to processing error.",
        suggestions: [],
        timeline_events: [],
        win_probability: 50,
        performance_score: 50
      }
    end
  end

  private

  def generate_ai_summary
    # Add safety checks for nil values
    return "Analysis unavailable - missing game data" if @game_info.nil? || @game_info.empty?
    
    champion = @game_info["champion_name"] || "Unknown"
    position = @game_info["position"] || "Unknown"
    result = @game_info["win"] ? "Victory" : "Defeat"
    
    # Debug logging
    Rails.logger.info "AI Summary Debug - champion: #{champion}, position: #{position}, win: #{@game_info['win']}"
    Rails.logger.info "AI Summary Debug - kills: #{@game_info['kills']}, deaths: #{@game_info['deaths']}, assists: #{@game_info['assists']}"
    Rails.logger.info "AI Summary Debug - cs: #{@game_info['cs']}, gold: #{@game_info['gold_earned']}, vision: #{@game_info['vision_score']}"
    
    # Safe duration calculation
    game_duration = @game_info["game_duration"] || @game_info["duration"] || 1800 # Default 30 min
    duration_minutes = game_duration.to_f / 60
    
    kills = @game_info['kills'] || 0
    deaths = @game_info['deaths'] || 0
    assists = @game_info['assists'] || 0
    cs = @game_info['cs'] || 0
    
    kda = "#{kills}/#{deaths}/#{assists}"
    # Analyze performance patterns
    kda_ratio = deaths > 0 ?
      ((kills + assists).to_f / deaths).round(2) :
      "Perfect"
    cs_per_min = (cs.to_f / duration_minutes).round(1)
    # Generate contextual summary based on performance and position
    if @game_info["win"]
      if kda_ratio.is_a?(Numeric) && kda_ratio > 2.0
        "Excellent #{champion} (#{position}) performance! Strong #{kda} KDA led to #{result.downcase}."
      else
        "Solid #{champion} (#{position}) game with #{kda} KDA for the #{result.downcase}."
      end
    else
      # Analyze what went wrong
      issues = []
      issues << "low CS efficiency" if cs_per_min < 5.0
      issues << "high death count" if @game_info["deaths"] > 7
      issues << "limited kill participation" if (@game_info["kills"] + @game_info["assists"]) < 8
      if issues.any?
        "Tough #{champion} (#{position}) game with #{kda} KDA. Focus on #{issues.join(' and ')} for improvement."
      else
        "Close #{champion} (#{position}) game with #{kda} KDA despite good individual performance. Team coordination could improve."
      end
    end
  end

  def generate_suggestions
    suggestions = []
    
    # Add safety checks for nil values
    return [] if @game_info.nil? || @game_info.empty?
    
    # Safe duration and CS calculation
    game_duration = @game_info["game_duration"] || @game_info["duration"] || 1800
    duration_minutes = game_duration.to_f / 60
    cs = @game_info["cs"] || 0
    cs_per_min = (cs.to_f / duration_minutes).round(1)
    # CS suggestions
    if cs_per_min < 6.0
      suggestions << {
        type: "warning",
        icon: "\u26A0\uFE0F",
        message: "CS efficiency below average (#{cs_per_min}/min). Focus on last-hitting practice.",
        timestamp: "Throughout game"
      }
    end
    # Death analysis
    if @game_info["deaths"] > 6
      suggestions << {
        type: "warning",
        icon: "\u26A0\uFE0F",
        message: "High death count (#{@game_info['deaths']}). Work on positioning and map awareness.",
        timestamp: "Multiple instances"
      }
    end
    # Vision suggestions
    if @game_info["vision_score"] < 20
      suggestions << {
        type: "improvement",
        icon: "\u{1F441}\uFE0F",
        message: "Low vision score (#{@game_info['vision_score']}). Place more wards for map control.",
        timestamp: "Throughout game"
      }
    end

    # Item suggestions based on final build
    item_suggestions = analyze_item_build
    suggestions.concat(item_suggestions)

    # Gold efficiency
    gold_earned = @game_info["gold_earned"] || 0
    gold_per_min = (gold_earned.to_f / duration_minutes).round(0)
    if gold_per_min < 300
      suggestions << {
        type: "improvement",
        icon: "\u{1F4B0}",
        message: "Gold income below average (#{gold_per_min}g/min). Focus on farming and objectives.",
        timestamp: "Throughout game"
      }
    end

    suggestions
  end

  def analyze_item_build
    suggestions = []
    items = @game_info["items"] || []

    # Check for defensive items if high deaths
    if @game_info["deaths"] > 5
      defensive_items = items.select { |item|
        defensive_item_ids.include?(item["item_id"])
      }

      if defensive_items.empty?
        suggestions << {
          type: "suggestion",
          icon: "\u{1F6E1}\uFE0F",
          message: "Consider building defensive items earlier with #{@game_info['deaths']} deaths.",
          timestamp: "Mid game"
        }
      end
    end

    # Check for boots
    boots = items.find { |item| boot_item_ids.include?(item["item_id"]) }
    unless boots
      suggestions << {
        type: "warning",
        icon: "\u{1F45F}",
        message: "No boots detected in final build. Mobility is crucial for positioning.",
        timestamp: "Early game"
      }
    end

    suggestions
  end

  def generate_timeline_events
    # Add safety check for nil values
    return [] if @game_info.nil? || @game_info.empty?
    
    game_duration = @game_info["game_duration"] || @game_info["duration"] || 1800
    duration_minutes = game_duration.to_f / 60

    events = []

    # Early game (0-15 min)
    events << {
      time: "5:00",
      type: "neutral",
      icon: "⏺️",
      description: "Early game phase"
    }

    # Mid game (15-25 min)
    if duration_minutes > 15
      events << {
        time: "15:00",
        type: "neutral",
        icon: "🟡",
        description: "Mid game transition"
      }
    end

    # Add death events if high death count
    if @game_info["deaths"] > 5
      critical_time = (duration_minutes * 0.6).round(0)
      events << {
        time: "#{critical_time}:00",
        type: "negative",
        icon: "🔻",
        description: "Critical deaths impacting game"
      }
    end

    # Game end
    end_time = "#{duration_minutes}:#{(@game_info['game_duration'] % 60).to_s.rjust(2, '0')}"
    events << {
      time: end_time,
      type: @game_info["win"] ? "positive" : "negative",
      icon: @game_info["win"] ? "✅" : "❌",
      description: @game_info["win"] ? "Victory achieved" : "Game lost"
    }

    events
  end

  def calculate_win_probability_timeline
    # Add safety check for nil values
    return 50 if @game_info.nil? || @game_info.empty?
    
    # Simplified win probability based on performance metrics
    base_probability = @game_info["win"] ? 65 : 35

    # Adjust based on KDA
    kills = @game_info["kills"] || 0
    deaths = @game_info["deaths"] || 0
    assists = @game_info["assists"] || 0
    kda_factor = deaths > 0 ? ((kills + assists).to_f / deaths) : 5.0

    kda_adjustment = (kda_factor - 1.0) * 10

    # Adjust based on CS
    game_duration = @game_info["game_duration"] || @game_info["duration"] || 1800
    duration_minutes = game_duration.to_f / 60
    cs = @game_info["cs"] || 0
    cs_per_min = cs.to_f / duration_minutes
    cs_adjustment = (cs_per_min - 5.0) * 5

    final_probability = [ base_probability + kda_adjustment + cs_adjustment, 95 ].min
    [ final_probability, 5 ].max.round(0)
  end

  def calculate_performance_score
    # Add safety check for nil values
    return 50 if @game_info.nil? || @game_info.empty?
    
    # Score out of 100 based on various metrics
    score = 50 # Base score

    # KDA contribution (30 points max)
    kills = @game_info["kills"] || 0
    deaths = @game_info["deaths"] || 0
    assists = @game_info["assists"] || 0
    kda_ratio = deaths > 0 ? ((kills + assists).to_f / deaths) : 5.0
    score += [ kda_ratio * 6, 30 ].min

    # CS contribution (20 points max)
    game_duration = @game_info["game_duration"] || @game_info["duration"] || 1800
    duration_minutes = game_duration.to_f / 60
    cs = @game_info["cs"] || 0
    cs_per_min = cs.to_f / duration_minutes
    score += [ (cs_per_min - 3.0) * 4, 20 ].min

    # Vision contribution (10 points max)
    vision_score = @game_info["vision_score"] || 0
    score += [ vision_score * 0.5, 10 ].min

    # Win bonus (10 points)
    score += 10 if @game_info["win"]

    [ score.round(0), 100 ].min
  end

  def defensive_item_ids
    [ 3047, 3742, 3193, 3065, 3156, 3026 ] # Common defensive items
  end

  def boot_item_ids
    [ 3020, 3047, 3006, 3009, 3111, 3117 ] # All boot types
  end
end
