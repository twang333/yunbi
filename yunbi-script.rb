require 'active_support'
require 'active_support/core_ext'
require 'peatio_client'
require 'pry'
require 'pry-nav'

class MyClient
  attr_accessor :client_public
  def initialize
    @client_public = PeatioAPI::Client.new endpoint: 'https://yunbi.com'
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

  def start
    # 策略
    balance = 10000.0
    volume  = 0
    market  = "qtumcny"
    period  = 60 
    p "current balance: #{balance}, volume: #{volume}"
    while true
      closing_price = fetch_closing_prices(market, period)
      ma_7  = moving_average(closing_price, 7)
      ma_30 = moving_average(closing_price, 30)
      buy_price, sell_price = fetch_ticker_price(market)
      p "check at #{Time.now} with price: #{sell_price}"

      if ma_7.first <= ma_30.first
        if volume > 0
          p "sell at time #{Time.now} with price: #{buy_price}"
          balance = volume * buy_price
          volume = 0
          p "current balance: #{balance}, volume: #{volume}"
        end
      else
        if balance > 0
          p "buy at time #{Time.now} with price: #{sell_price}"
          volume = balance/sell_price
          balance = 0
          p "current balance: #{balance}, volume: #{volume}"
        end
      end

      sleep(60.seconds)
    end
  end

end

c = MyClient.new
c.start

