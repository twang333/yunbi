require 'active_support'
require 'active_support/core_ext'
require 'peatio_client'
require 'yaml'

require 'optparse'

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

  def initialize(options)
    @client_public = PeatioAPI::Client.new endpoint: 'https://yunbi.com'
    @conf = YAML.load_file("setting.yml")
    access_key = @conf[options[:env]]['access']
    access_token = @conf[options[:env]]['token']

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
    raw_data.map {|item| item[4]}.reverse
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

  def start
    # 策略
    market = @conf['market']
    coin   = @conf['coin']
    period = @conf['period']
    while true
      accounts = get_accounts
      cny_balance = accounts.detect {|item| item['currency'] == 'cny' }['balance'].to_f
      coin_balance = accounts.detect {|item| item['currency'] == coin }['balance'].to_f
      p "cny_balance: #{cny_balance}; coin_balance: #{coin_balance}"

      if cny_balance == 0 && coin_balance == 0
        p "cancel orders"
        cancel_all_orders
        sleep(5)
      end

      closing_price = fetch_closing_prices(market, period)
      ma_7  = moving_average(closing_price, 7)
      ma_30 = moving_average(closing_price, 30)
      buy_price, sell_price = fetch_ticker_price(market)

      if ma_7.first <= ma_30.first
        if coin_balance > 0
          p "sell at time #{Time.now} with price: #{buy_price}"
          sell(market, coin_balance, buy_price)
        end
      else
        if cny_balance > 1
          p "buy at time #{Time.now} with price: #{sell_price}"
          buy(market, cny_balance, sell_price)
        end
      end

      sleep((5*60).seconds)
    end
  end

end

c = MyClient.new(options)
c.start

