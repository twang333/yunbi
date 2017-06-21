require 'active_support'
require 'active_support/core_ext'
require 'peatio_client'
require 'yaml'

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

  def initialize(options)
    @client_public = PeatioAPI::Client.new endpoint: 'https://yunbi.com'
    @conf = YAML.load_file("setting.yml")
    access_key = @conf[options[:env]]['access']
    access_token = @conf[options[:env]]['token']
    @log = Logger.new('logs/yunbi.log', 'daily')

    options = {
      access_key: access_key,
      secret_key: access_token,
      endpoint: 'https://yunbi.com',
      timeout: 60
    }

    @client = PeatioAPI::Client.new options
  end

  def fetch_closing_prices(market, period = 15, limit = 30)
    raw_data = @client_public.get_public '/api/v2/k', market: market, period: period, limit: limit
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
    first = prices[0...k].sum.to_f/k
    result = [first]
    param = (k-1).to_f / (k+1)
    (l-k).times do |i|
      result << result.last * param + prices[k+i] * (1 - param) 
    end
    return result
  end

  def buy(market, total, price)
    volume = total / price
    @client.post '/api/v2/orders', market: market, side: 'buy', volume: volume, price: price
  end

  def sell(market, volume, price)
    @client.post '/api/v2/orders', market: market, side: 'sell', volume: volume, price: price
  end

  def cancel_all_orders
    @client.post '/api/v2/orders/clear'
  end

  def get_accounts
    data = @client.get '/api/v2/members/me'
    data['accounts']
  end

  def strategy(market, period, coin_balance, cny_balance, strategy = 'moving_average')
    closing_price = fetch_closing_prices(market, period)
    ma_7  = self.send(:"#{strategy}", closing_price, 7)
    ma_30 = self.send(:"#{strategy}", closing_price, 30)
    buy_price, sell_price = fetch_ticker_price(market)

    if coin_balance > 0.001
      if ma_7[-1] < ma_30[-1]
        @log.info "sell with price: #{buy_price}, ma_7: #{ma_7[-1]}; ma_30: #{ma_30[-1]}; strategy: #{strategy}"
        sell(market, coin_balance, buy_price)
      end
    end

    if cny_balance > 1
      if ma_7[-1] > ma_30[-1] && ma_7[-2] < ma_30[-2]
        @log.info "buy with price: #{sell_price}, ma_7: #{ma_7[-1]}; ma_30: #{ma_30[-1]}; strategy: #{strategy}"
        buy(market, cny_balance, sell_price)
      end
    end
  end

  def start
    market         = @conf['market']
    coin           = @conf['coin']
    period         = @conf['period']
    trade_strategy = @conf['strategy']

    accounts = get_accounts
    cny_balance = accounts.detect {|item| item['currency'] == 'cny' }['balance'].to_f
    coin_balance = accounts.detect {|item| item['currency'] == coin }['balance'].to_f
    @log.info "cny_balance: #{cny_balance}; coin_balance: #{coin_balance}"

    if cny_balance == 0 && coin_balance == 0
      @log.infop "cancel all orders"
      cancel_all_orders
      sleep(5)
    end

    # strategy(market, period, coin_balance, cny_balance, 'moving_average')
    strategy(market, period, coin_balance, cny_balance, trade_strategy)
  end

end

c = MyClient.new(options)
c.start
