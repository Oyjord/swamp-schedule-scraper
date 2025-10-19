require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc  = Nokogiri::HTML(html)

  # Find the SCORING table (has header "SCORING")
  scoring_table = doc.css('table').find { |t| t.text.include?("SCORING") }
  return nil unless scoring_table

  # The scoring table layout: header row, then header numbers row, then two team rows
  scoring_rows = scoring_table.css('tr')
  # Defensive: find the two rows containing team names (skip header rows)
  team_rows = scoring_rows.select { |r| r.css('td').any? && r.text.strip =~ /\w/ }[1..2] # pick the first two data rows
  return nil unless team_rows && team_rows.size >= 2

  # Extract full team names and their final totals (last TD is "T")
  away_full = team_rows[0].css('td')[0]&.text&.strip || ""
  home_full = team_rows[1].css('td')[0]&.text&.strip || ""
  away_total = team_rows[0].css('td').last&.text&.strip.to_i
  home_total = team_rows[1].css('td').last&.text&.strip.to_i

  # Detect OT / SO
  overtime_type = nil
  overtime_type = "SO" if doc.text.include?("SHOOTOUT")
  overtime_type ||= "OT" if scoring_table.text.include?("OT") # OT column present

  # Now parse goal details from the Goals table (rows with Goals/Assists)
  goal_table = doc.css('table').find do |t|
    header = t.at_css('tr')
    header && header.text.include?('Goals') && header.text.include?('Assists')
  end

  home_goals = []
  away_goals = []

  if goal_table
    goal_rows = goal_table.css('tr')[1..] || []
    goal_rows.each do |row|
      tds = row.css('td')
      next unless tds.size >= 7

      team_abbrev = tds[3].text.strip # e.g. "GVL" or "SAV"
      scorer = tds[5].text.split('(').first&.strip || ""
      assists = tds[6].text.strip
      entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

      # Map the team abbreviation to side (away/home) dynamically.
      # Heuristic: check if the abbrev corresponds to Greenville / Savannah specifically,
      # otherwise fall back to comparing known names in the full team strings.
      side = nil
      case team_abbrev.upcase
      when "GVL", "GVL."
        # if away_full contains 'Greenville' then GVL is away, else home
        side = away_full.downcase.include?("greenville") ? :away : :home
      when "SAV", "SAV."
        side = away_full.downcase.include?("savannah") ? :away : :home
      else
        # Generic fallback: if full names contain a short form of the abbrev's letters,
        # try to detect: e.g. 'TBL' vs 'Tampa' etc. If we can't detect, default to putting
        # into away if the first scoring row's team matches the common known name.
        if away_full.downcase.include?(team_abbrev.downcase[0,3])
          side = :away
        elsif home_full.downcase.include?(team_abbrev.downcase[0,3])
          side = :home
        else
          # fallback: compare common tokens
          # (This is conservative — not expected to trigger for Greenville/Savannah)
          side = :away
        end
      end

      if side == :away
        away_goals << entry
      else
        home_goals << entry
      end
    end
  end

  # Use totals read from SCORING table (these already include SO decision)
  away_score = away_total
  home_score = home_total

  # Build result string including final score and overtime type if present
  if away_score > home_score
    diff_str = "#{away_score}-#{home_score}"
    result = overtime_type ? "W(#{overtime_type}) #{diff_str}" : "W #{diff_str}"
    winner = :away
  elsif away_score < home_score
    diff_str = "#{away_score}-#{home_score}"
    result = overtime_type ? "L(#{overtime_type}) #{diff_str}" : "L #{diff_str}"
    winner = :home
  else
    # tie (shouldn't happen for finished games with SO/OT present)
    result = "T #{away_score}-#{home_score}"
    winner = nil
  end

  {
    "game_id" => game_id.to_i,
    "date" => nil,                 # enrich_all.rb will set date/opponent/location
    "home_team" => home_full,
    "away_team" => away_full,
    "home_score" => home_score,
    "away_score" => away_score,
    "home_goals" => home_goals,
    "away_goals" => away_goals,
    "game_report_url" => url,
    "status" => "Final",
    "result" => result,
    "overtime_type" => overtime_type,
    "winner" => winner == :away ? away_full : (winner == :home ? home_full : nil)
  }
rescue => e
  warn "⚠️ Failed to parse game sheet for game_id #{game_id}: #{e}"
  nil
end

if ARGV.empty?
  warn "Usage: ruby enrich_game.rb <game_id>"
  exit 1
end

game_id = ARGV[0]
data = parse_game_sheet(game_id)
# don't print date here; enrich_all.rb will populate date/opponent/location fields
puts JSON.pretty_generate(data) if data
