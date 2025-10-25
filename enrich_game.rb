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

  # derive the exact abbreviations/labels used for goal attribution
  away_label = away_team.gsub(/\s+/, '').upcase
  home_label = home_team.gsub(/\s+/, '').upcase

  # ---------- GOAL SUMMARY table ----------
goal_table = doc.css('table').find do |t|
  header = t.at_css('tr')
  header && header.text.match?(/Goal|Scorer/i)
end

home_goals, away_goals = [], []

if goal_table
  headers = goal_table.css('tr').first.css('td,th').map { |td| td.text.strip }
  idx_team   = headers.index { |h| h.match?(/Team/i) } || 3
  idx_goal   = headers.index { |h| h.match?(/Goal|Scorer/i) } || 5
  idx_assist = headers.index { |h| h.match?(/Assist/i) } || 6

  greenville_is_home = game["location"] == "Home"

  goal_table.css('tr')[1..]&.each do |row|
    tds = row.css('td')
    next if tds.size < [idx_team, idx_goal, idx_assist].max + 1

    team_code = tds[idx_team]&.text&.gsub(/\u00A0/, '')&.strip&.upcase
    scorer    = tds[idx_goal]&.text&.split('(')&.first&.strip
    assists   = tds[idx_assist]&.text&.strip
    next if scorer.nil? || scorer.empty?

    entry = assists.nil? || assists.empty? ? scorer : "#{scorer} (#{assists})"

    if team_code == "GVL"
      greenville_is_home ? home_goals << entry : away_goals << entry
    else
      greenville_is_home ? away_goals << entry : home_goals << entry
    end
  end
end

  # ---------- META info ----------
  meta_table = doc.css('table').find { |t| t.text.match?(/Game Start|Game End|Game Length/i) }
  meta = {}
  if meta_table
    meta_table.css('tr').each do |r|
      tds = r.css('td').map { |td| td.text.gsub("\u00A0", ' ').strip }
      next unless tds.size >= 2
      meta[tds[0].gsub(':', '').strip] = tds[1].strip
    end
  end

  game_start_raw = meta['Game Start']
  game_end_raw   = meta['Game End']
  game_length_raw = meta['Game Length']

  # ---------- determine scheduled start ----------
  scheduled_start = nil
begin
  scheduled_start = Time.parse(game["scheduled_start"]).utc if game && game["scheduled_start"]
rescue
  scheduled_start = nil
end

now = Time.now.utc

  # ---------- status ----------
has_final_indicator =
  (game_length_raw && game_length_raw.match?(/\d+:\d+/)) ||
  (game_end_raw && !game_end_raw.empty?) ||
  (doc.text =~ /\bFinal\b/i && doc.text !~ /not available/i)

has_scores = (home_score + away_score) > 0 || home_goals.any? || away_goals.any?


status =
  if doc.text.include?("This game is not available")
    "Upcoming"
  elsif scheduled_start && now < scheduled_start
    "Upcoming"
  elsif has_final_indicator
    "Final"
  elsif scheduled_start && now >= scheduled_start
    "Live"
  else
    "Upcoming"
  end


if game_id.to_s == "24330"
  warn "🧪 DEBUG FOR GAME #{game_id}"
  warn "🧪 status: #{status}"
  warn "🧪 scheduled_start: #{scheduled_start.inspect}"
  warn "🧪 home_score: #{home_score}, away_score: #{away_score}"
  warn "🧪 home_goals: #{home_goals.inspect}"
  warn "🧪 away_goals: #{away_goals.inspect}"
  warn "🧪 has_final_indicator: #{has_final_indicator}"
  warn "🧪 has_scores: #{has_scores}"
end


  # ---------- Detect OT / SO ----------
normalize = ->(v) { v.to_s.gsub(/\u00A0/, '').strip }

# ✅ Only read OT/SO columns if they exist
ot_away = away_cells.length > 5 ? normalize.call(away_cells[4]) : ""
ot_home = home_cells.length > 5 ? normalize.call(home_cells[4]) : ""
so_away = away_cells.length > 5 ? normalize.call(away_cells[5]) : ""
so_home = home_cells.length > 5 ? normalize.call(home_cells[5]) : ""

# ✅ Only assign overtime_type if game is Final
overtime_type = nil
if status == "Final"
  so_goals = so_away.to_i + so_home.to_i
  ot_goals = ot_away.to_i + ot_home.to_i

  if so_goals > 0
    overtime_type = "SO"
  elsif ot_goals > 0
    overtime_type = "OT"
  end
end

  # ---------- Build result ----------
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

# ---------- CLI ----------
if ARGV.empty?
  warn "Usage: ruby enrich_game.rb <game_id>"
  exit 1
end

game_id = ARGV[0]
game = nil
if File.exist?("swamp_schedule.json")
  begin
    games = JSON.parse(File.read("swamp_schedule.json"))
    game = games.find { |g| g["game_id"].to_s == game_id.to_s }
  rescue
    game = nil
  end
end

data = parse_game_sheet(game_id, game)
puts JSON.pretty_generate(data) if data
