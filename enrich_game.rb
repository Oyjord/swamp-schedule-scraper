require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc = Nokogiri::HTML(html)
  debug = ENV["DEBUG"] == "true"

  # --- Find scoring summary table ---
  rows = doc.css('table').find do |table|
    header = table.at_css('tr')
    header && header.text.include?('Goals') && header.text.include?('Assists')
  end&.css('tr')&.drop(1) || []

  puts "🧪 Found #{rows.size} scoring rows" if debug

  if rows.empty?
    File.write("/tmp/debug_#{game_id}.html", html)
    puts "⚠️ No scoring rows found — dumped HTML to /tmp/debug_#{game_id}.html" if debug
  end

  home_goals, away_goals = [], []

  # --- Parse goals ---
  rows.each do |row|
    tds = row.css('td')
    next unless tds.size >= 7

    team = tds[3].text.strip
    scorer = tds[5].text.split('(').first.strip
    assists = tds[6].text.strip
    entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

    puts "→ team: #{team.inspect}, scorer: #{scorer.inspect}, assists: #{assists.inspect}" if debug

    # You may adjust this to dynamically detect home/away, but for now:
    if team == "GVL"
      home_goals << entry
    elsif !team.empty?
      away_goals << entry
    end
  end

  home_score = home_goals.size
  away_score = away_goals.size

  # --- Detect overtime / shootout ---
  overtime_type = nil
  result = nil

  full_text = doc.text

  if full_text.include?("Shootout Summary")
    overtime_type = "SO"
  elsif full_text.include?("Overtime") || full_text.include?("OT Period")
    overtime_type = "OT"
  end

  # --- Detect winner ---
  # The site’s header typically lists team names and scores
  header_text = doc.css('h3, h2, h4, b').map(&:text).join(" ")
  winner = nil

  if header_text =~ /Final/i
    # Example: "Final - Greenville 5 Savannah 4 (SO)"
    if header_text =~ /Greenville.*?(\d+).*?Savannah.*?(\d+)/
      gvl_score = $1.to_i
      sav_score = $2.to_i
      winner = gvl_score > sav_score ? "away" : "home"
    elsif header_text =~ /Savannah.*?(\d+).*?Greenville.*?(\d+)/
      sav_score = $1.to_i
      gvl_score = $2.to_i
      winner = gvl_score > sav_score ? "away" : "home"
    end
  else
    winner = home_score > away_score ? "home" : "away"
  end

  # --- Compose result ---
  if overtime_type == "SO"
    result = winner == "away" ? "W(SO)" : "L(SO)"
  elsif overtime_type == "OT"
    result = winner == "away" ? "W(OT)" : "L(OT)"
  else
    result = winner == "away" ? "W" : "L"
  end

  {
    game_id: game_id.to_i,
    home_score: home_score,
    away_score: away_score,
    home_goals: home_goals,
    away_goals: away_goals,
    game_report_url: url,
    status: "Final",
    result: result,
    overtime_type: overtime_type
  }
rescue => e
  puts "⚠️ Failed to parse game sheet for game_id #{game_id}: #{e}"
  nil
end

# --- CLI entrypoint ---
if ARGV.empty?
  puts "Usage: ruby enrich_game.rb <game_id>"
  exit 1
end

game_id = ARGV[0]
enriched = parse_game_sheet(game_id)
puts JSON.pretty_generate(enriched) if enriched
