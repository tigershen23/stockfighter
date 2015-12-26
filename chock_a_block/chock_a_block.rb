require "httparty"
require "trollop"
require "dotenv"
Dotenv.load

opts = Trollop::options do
  opt :price, "Price to buy stock at", :type => :integer
  opt :quantity, "Amount of stock to buy", :type => :integer, :default => 100_000
end

API_KEY = ENV["STOCKFIGHTER_API_KEY"]
BASE_URL = ENV["STOCKFIGHTER_BASE_URL"]
VENUE = "HFNBEX"
STOCK = "KTI"
ACCOUNT = "KFB69080388"

TOTAL_QTY_DESIRED = opts[:quantity]
total_qty_purchased = 0
create_order_url = "#{BASE_URL}/venues/#{VENUE}/stocks/#{STOCK}/orders"

def _create_order(total_qty_purchased, price)
  qty_remaining = TOTAL_QTY_DESIRED - total_qty_purchased
  qty_to_buy = qty_remaining < 5000 ? qty_remaining : rand(1000..5000)
  {
    "account" => ACCOUNT,
    "venue" => VENUE,
    "symbol" => STOCK,
    "price" => price,
    "qty" => qty_to_buy,
    "direction" => "buy",
    "orderType" => "limit",
  }
end

authentication_headers = {"X-Starfighter-Authorization" => API_KEY}

while total_qty_purchased < TOTAL_QTY_DESIRED
  order = _create_order(total_qty_purchased, opts[:price])
  response = HTTParty.post(create_order_url,
                           :body => JSON.dump(order),
                           :headers => authentication_headers
                          )
  current_order = JSON.parse(response.body)
  total_qty_purchased += order["qty"]
  puts "submitted order for #{order["qty"]}. ID: #{current_order["id"]}. Purchased: #{total_qty_purchased}, remaining: #{TOTAL_QTY_DESIRED - total_qty_purchased}"
  current_order_id = current_order["id"]

  order_status_url = "#{BASE_URL}/venues/#{VENUE}/stocks/#{STOCK}/orders/#{current_order_id}"

  order_open = current_order["open"]

  while order_open
    response = HTTParty.get(order_status_url, headers: authentication_headers)
    current_order_status = JSON.parse(response.body)
    order_open = current_order_status["open"]
    puts "Status for #{current_order_id} (at $#{opts[:price]}): Filled #{current_order_status["totalFilled"]} out of #{current_order_status["originalQty"]}"
    sleep(3)
  end

  sleep(rand(10..20))
end

