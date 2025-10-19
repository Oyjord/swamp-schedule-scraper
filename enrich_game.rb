# enrich_game.rb
require 'open-uri'
require 'nokogiri'
require 'json'
require 'time'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id, game = nil)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc  = Nokogiri::HTML(html)

  # ---------- SCORING table ----------
  scoring_table = doc.css('table').find { |t| t.text.include?('SCORING') }
  unless scoring_table
    return {
      "game_id" => game_id.to_i,
      "status" => "Upcoming",
      "home_score" => 0,
      "away_score" => 0,
      "home_goals" => [],
      "away_goals" => [],
      "overtime_type" => nil,
      "result" => nil,
      "game_report_url" => url
    }
  end

  rows = scoring_table.css('tr')[2..3]
  raise "Unexpected scoring table structure for game #{game_id}" unless rows && rows.size == 2

  away_cells = rows[0].css('td').map { |td| td.text.gsub("\u00A0", ' ').strip }
  home_cells = rows[1].css('td').map { |td| td.text.gsub("\u00A0", ' ').strip }

  away_team = away_cells[0]
  home_team = home_cells[0]
  away_score = away_cells.last.to_i
  home_score = home_cells.last.to_i

  # ---------- GOAL SUMMARY table (dynamic detection) ----------
  goal_table = doc.css('table').find do |t|
    header = t.at_css('tr')
    header && header.text.match?(/Goal|Scorer/i)
  end

  home_goals = []
  away_goals = []

  if goal_table
    header_cells = goal_table.css('tr').first.css('td,th').map { |td| td.text.strip }
    idx_team   = header_cells.index { |h| h.match?(/Team/i) } || 3
    idx_goal   = header_cells.index { |h| h.match?(/Goal|Scorer/i) } || 5
    idx_assist = header_cells.index { |h| h.match?(/Assist/i) } || 6

    short_away = away_team.gsub(/[^A-Za-z]/, '').upcase[0,3]
    short_home = home_team.gsub(/[^A-Za-z]/, '').upcase[0,3]

    goal_table.css('tr')[1..]&.each do |row|
      tds = row.css('td')
      next if tds.size < [idx_team, idx_goal, idx_assist].max + 1

      team_code = tds[idx_team]&.text&.gsub(/\u00A0/, '')&.strip&.upcase
      scorer    = tds[idx_goal]&.text&.split('(')&.first&.strip
      assists   = tds[idx_assist]&.text&.strip
      next if scorer.nil? || scorer.empty?

      entry = assists.nil? || assists.empty? ? "#{scorer}" : "#{scorer} (#{assists})"

      if team_code.start_with?(short_away) || away_team.upcase.include?(team_code)
        away_goals << entry
      elsif team_code.start_with?(short_home) || home_team.upcase.include?(team_code)
        home_goals << entry
      else
        # fallback: assign to whichever side has fewer goals so far
        if away_goals.size <= home_goals.size
          away_goals << entry
        else
          home_goals << entry
        end
      end
    end
  end

  # ---------- META: Game Start / End / Length ----------
  meta_table = doc.css('table').find { |t| t.text.match?(/Game Start|Game End|Game Length/i) }
  meta = {}
  if meta_table
    meta_table.css('tr').each do |r|
      tds = r.css('td').map { |td| td.text.gsub("\u00A0", ' ').strip }
      next unless tds.size >= 2
      label = tds[0].gsub(':', '').strip
      value = tds[1].strip
      meta[label] = value
    end
  end

  game_start_raw = meta['Game Start'] || nil
  game_end_raw   = meta['Game End']   || nil
  game_length_raw = meta['Game Length'] || nil

  # ---------- determine scheduled start ----------
  scheduled_start = nil
  begin
    if game && game["date"] && game_start_raw && !game_start_raw.empty?
      date_str = game["date"].gsub('.', '').strip
      year = (date_str =~ /,\s*\d{4}/) ? "" : ", #{Time.now.year}"
      scheduled_start = Time.parse("#{date_str}#{year} #{game_start_raw}")
    end
  rescue
    scheduled_start = nil
  end

  scheduled_date = nil
  begin
    if game && game["date"]
      ds = game["date"].gsub('.', '').strip
      if ds =~ /\w+\s+\d{1,2}/
        scheduled_date = Date.parse("#{ds} #{Time.now.year}")
      end
    end
  rescue
    scheduled_date = nil
  end

  # ---------- determine status ----------
  has_final_indicator =
    (game_length_raw && game_length_raw.match?(/\d+:\d+/)) ||
    (game_end_raw && !game_end_raw.empty?) ||
    (doc.text =~ /\bFinal\b/i && doc.text !~ /not available/i)

  has_scores = (home_score + away_score) > 0 || home_goals.any? || away_goals.any?

  now = Time.now
  status =
    if doc.text.include?("This game is not available")
      "Upcoming"
    elsif has_final_indicator
      "Final"
    elsif scheduled_start
      now < scheduled_start ? "Upcoming" : "Live"
    elsif scheduled_date
      if Date.today < scheduled_date
        "Upcoming"
      elsif Date.today > scheduled_date
        has_scores ? "Final" : "Upcoming"
      else
        has_scores ? "Live" : "Upcoming"
      end
    else
      has_scores ? (has_final_indicator ? "Final" : "Live") : "Upcoming"
    end

  # ---------- Detect OT / SO (only relevant for Final) ----------
  normalize = ->(val) { val.to_s.gsub(/\u00A0/, '').strip }
  ot_val_away = away_cells.length > 4 ? normalize.call(away_cells[4]) : nil
  ot_val_home = home_cells.length > 4 ? normalize.call(home_cells[4]) : nil
  so_val_away = away_cells.length > 5 ? normalize.call(away_cells[5]) : nil
  so_val_home = home_cells.length > 5 ? normalize.call(home_cells[5]) : nil

  so_goals = (so_val_away.to_i + so_val_home.to_i)
  ot_has_real_value =
    ((ot_val_away =~ /\d+/) && ot_val_away.to_i > 0) ||
    ((ot_val_home =~ /\d+/) && ot_val_home.to_i > 0)
  overtime_type = nil
  if status == "Final"
    overtime_type = "SO" if so_goals > 0
    overtime_type = "OT" if overtime_type.nil? && ot_has_real_value
  end

  # ---------- Build result (only for Final) ----------
  result = nil
  if status == "Final"
    greenville_is_home = home_team =~ /Greenville/i
    greenville_score = greenville_is_home ? home_score : away_score
    opponent_score   = greenville_is_home ? away_score : home_score

    prefix =
      if overtime_type == "SO"
        greenville_score > opponent_score ? "W(SO)" : "L(SO)"
      elsif overtime_type == "OT"
        greenville_score > opponent_score ? "W(OT)" : "L(OT)"
      else
        greenville_score > opponent_score ? "W" : "L"
      end

    result = "#{prefix} #{[greenville_score, opponent_score].max}-#{[greenville_score, opponent_score].min}"
  end

  # ---------- Final JSON ----------
  {
    "game_id" => game_id.to_i,
    "status" => status,
    "home_team" => home_team,
    "away_team" => away_team,
    "home_score" => home_score,
    "away_score" => away_score,
    "home_goals" => home_goals,
    "away_goals" => away_goals,
    "overtime_type" => overtime_type,
    "result" => result,
    "game_report_url" => url
  }
rescue => e
  warn "⚠️ Failed to parse game sheet for #{game_id}: #{e}"
  nil
end

# ---------- CLI entry ----------
if ARGV.empty?
  warn "Usage: ruby enrich_game.rb <game_id>"
  exit 1
end

game_id = ARGV[0]
game = nil
if File.exist?("swamp_game_ids.json")
  begin
    games = JSON.parse(File.read("swamp_game_ids.json"))
    game = games.find { |g| g["game_id"].to_s == game_id.to_s }
  rescue
    game = nil
  end
end

data = parse_game_sheet(game_id, game)
puts JSON.pretty_generate(data) if data
