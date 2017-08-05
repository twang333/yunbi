require 'active_support'
require 'active_support/core_ext'
require 'peatio_client'
require 'yaml'
require 'slack-notifier'

require 'optparse'
require 'logger'

options = {:env => 'test'}
OptionParser.new do |opts|
  opts.banner = "Usage: [options]"

  opts.on("-e", "--require env", "env: can be test or prd") do |env|
    options[:env] = env
  end
end.parse!

class MyClient
  attr_accessor :client_public
  attr_accessor :client
  attr_accessor :conf
  attr_accessor :log
  attr_accessor :markets
  attr_accessor :slack_notifier
  attr_accessor :stop_loss
  attr_accessor :stop_profit
  attr_accessor :strategy

  def initialize(options)
    @client_public  = PeatioAPI::Client.new endpoint: 'https://yunbi.com'
    @conf           = YAML.load_file("setting.yml")
    access_key      = @conf[options[:env]]['access']
    access_token    = @conf[options[:env]]['token']
    @markets        = @conf[options[:env]]['markets']
    @stop_loss      = @conf[options[:env]]['loss']
    @stop_profit    = @conf[options[:env]]['profit']
    @strategy       = @conf[options[:env]]['strategy']
    @log            = Logger.new('logs/yunbi.log', 'daily')
    hook_url        = @conf['slack_hook_url']
    @slack_notifier = Slack::Notifier.new hook_url, channel: "#general"

    options = {
      access_key: access_key,
      secret_key: access_token,
      endpoint: 'https://yunbi.com',
      timeout: 60
    }

    @client = PeatioAPI::Client.new options
  end

  def get_markets
    @client_public.get_public '/api/v2/markets'
  end

  def fetch_closing_prices(market, period = 15, limit = 30)
    raw_data = @client_public.get_public '/api/v2/k', market: market, period: period, limit: limit

    # api data timestamp should be less then 60 min
    api_timestamp = raw_data.map { |item| item[0] }.last
    delay = Time.now.to_i - api_timestamp
    if  delay > 60 * 60 * 1.5
      raise "bad timestamp for k api, delay: #{delay}"
    end

    raw_data.map {|item| item[4]}
  end

  def fetch_ticker_price(market)
    raw_data = @client_public.get_public "/api/v2/tickers/#{market}"

    [raw_data["ticker"]["buy"].to_f, raw_data["ticker"]["sell"].to_f]
  end

  def moving_average(prices, k)
    l = prices.size
    return [] if l < k
    first = prices[0...k].sum.to_f/k
    result = [first]
    (l - k).times do |i|
      result << result.last - prices[i].to_f/k + prices[k+i].to_f/k
    end
    return result
  end

  def exponential_moving_average(prices, k)
    l = prices.size
    return [] if l < k
    first = (prices[0...k].sum.to_f/k).round(4)
    result = [first]
    param = (k-1).to_f / (k+1)
    (l-k).times do |i|
      result << (result.last * param + prices[k+i] * (1 - param)).round(4)
    end
    return result
  end

  def buy(market, total, price)
    @slack_notifier.ping("buy #{market} with price: #{price}, budget: #{total}")
    volume = total / price
    @client.post '/api/v2/orders', market: market, side: 'buy', volume: volume, price: price
  end

  def sell(market, volume, price)
    @slack_notifier.ping("sell #{market} with price: #{price}, volume: #{volume}")
    @client.post '/api/v2/orders', market: market, side: 'sell', volume: volume, price: price
  end

  def cancel_all_orders
    @client.post '/api/v2/orders/clear'
  end

  def get_accounts
    data = @client.get '/api/v2/members/me'
    accounts_hash = {}
    data['accounts'].inject(accounts_hash) do |result, account|
      result[account["currency"]] = {
        "balance" => account["balance"].to_f,
        "locked"  => account["locked"].to_f
      }
      result
    end
    accounts_hash
  end

  def strategy(market, strategy = 'moving_average')
    closing_price = fetch_closing_prices(market, 60, 60)
    ma_7  = self.send(:"#{strategy}", closing_price, 7)
    ma_30 = self.send(:"#{strategy}", closing_price, 30)

    buy_price, sell_price = fetch_ticker_price(market)

    ratio = ma_7[-1]/ma_30[-1]
    if ratio > 0.99 && ma_7[-1]/ma_7[-2] > 1 && sell_price <= ma_7[-1]
      @slack_notifier.ping("good time to buy #{market}")
      buy(market, 1000, sell_price)
      return
    end
  end

  def monitor(market, coin_balance, price)
    buy_price, sell_price = fetch_ticker_price(market)

    if sell_price / price >= (1 + @stop_profit)
      @slack_notifier.ping "profit: #{market}, sell: #{sell_price}"
      sell(market, coin_balance, sell_price)
      return
    end

    if buy_price / price <= (1 - @stop_loss)
      @slack_notifier.ping "loss: #{market}, sell: #{buy_price}"
      sell(market, coin_balance, buy_price)
      return
    end

  end

  def start
    coins = @markets.map{|m| m['coin']}

    accounts = get_accounts
    coin_locked = coins.sum {|l| accounts[l]['locked']}

    if accounts['cny']['locked'] > 0 || coin_locked > 0
      @log.info "cancel all orders due to locked"
      cancel_all_orders

      sleep(5)

      # reload accounts
      accounts = get_accounts
    end

    # handle deviation
    @markets.each do |market|
      deviation = market['deviation']
      if accounts[market['coin']]['balance'] < eviation
        accounts[market['coin']]['balance'] = 0
      end
    end

    @markets.each do |opt|
      market       = opt['market']
      coin         = opt['coin']
      price        = opt['price']
      coin_balance = accounts[coin]['balance']

      monitor(market, coin_balance, price)
    end

    existing_markets = @markets.map { |opt| opt['market'] }
    all_markets = get_markets
    all_markets.each do |market|
      m = market['id']
      next if existing_markets.include?(m)
      strategy(m, @strategy)
    end

  end

end

c = MyClient.new(options)
begin
  c.start
rescue Exception => e
  c.slack_notifier.ping e
end