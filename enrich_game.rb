require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc = Nokogiri::HTML(html)
  debug = ENV["DEBUG"] == "true"

  # ✅ Parse GOALS table
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

  rows.each do |row|
    tds = row.css('td')
    next unless tds.size >= 7

    team = tds[3].text.strip
    scorer = tds[5].text.split('(').first.strip
    assists = tds[6].text.strip
    entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

    puts "→ team: #{team.inspect}, scorer: #{scorer.inspect}, assists: #{assists.inspect}, entry: #{entry.inspect}" if debug

    if team == "GVL"
      home_goals << entry
    elsif team
      away_goals << entry
    end
  end

  home_score = home_goals.size
  away_score = away_goals.size

  # ✅ Parse SCORING table for shootout winner
  so_winner = nil

  scoring_table = doc.css('table').find do |table|
    table.text.include?("SCORING") && table.text.include?("SO")
  end

  if scoring_table
    score_rows = scoring_table.css('tr').select { |r| r.css('td').size == 7 }
    score_rows.each do |row|
      cells = row.css('td').map(&:text).map(&:strip)
      team = cells[0]
      so = cells[5].to_i
      puts "🧪 SCORING row: team=#{team.inspect}, SO=#{so}" if debug
      if so > 0
        so_winner = team.include?("Greenville") ? "GVL" : "OPP"
      end
    end
  end

  {
    game_id: game_id.to_i,
    home_score: home_score,
    away_score: away_score,
    home_goals: home_goals,
    away_goals: away_goals,
    result: so_winner == "GVL" ? "W(SO)" : so_winner == "OPP" ? "L(SO)" : nil,
    overtime_type: so_winner ? "SO" : nil,
    game_report_url: url
  }
rescue => e
  puts "⚠️ Failed to parse game sheet for game_id #{game_id}: #{e}"
  nil
end

if ARGV.empty?
  puts "Usage: ruby enrich_game.rb <game_id>"
  exit 1
end

game_id = ARGV[0]
enriched = parse_game_sheet(game_id)
puts JSON.pretty_generate(enriched) if enriched
