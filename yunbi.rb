require 'active_support'
require 'active_support/core_ext'
require 'peatio_client'
require 'pry'
require 'pry-nav'

client_public = PeatioAPI::Client.new endpoint: 'https://yunbi.com'
markets = client_public.get_public '/api/v2/markets'

access_key = 'your access key'
access_token = 'your access token'

options = {
  access_key: access_key, 
  secret_key: access_token, 
  endpoint: 'https://yunbi.com', 
  timeout: 60
}

$client = PeatioAPI::Client.new options


def buy(market, total, price) 
  volume = total / price
  $client.post '/api/v2/orders', market: market, side: 'buy', volume: volume, price: price 
end

def sell(market, volume, price)
  $client.post '/api/v2/orders', market: market, side: 'sell', volume: volume, price: price 
end

# buy($market, total, price) 
binding.pry

$total = 5000.to_f
$market = 'btccny'
$market = 'gxscny' #''
$price = 4 

{
  15000.to_f => 4,
  10000.to_f => 5,
  5000.to_f => 6,
  5000.to_f => 7
}.each do |total, price|
  # buy($market, total, price)
end


# $client.post '/api/v2/orders', market: $market, side: 'sell', volume: $volume, price: $price 


orders = $client.get '/api/v2/orders', market: $market


puts orders

