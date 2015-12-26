require "httparty"
require "dotenv"
Dotenv.load

module Stockfighter
  class API
    BASE_URL = "https://api.stockfighter.io/ob/api"

    def initialize(key:, account:, symbol:, venue:)
      @api_key = key
      @account = account
      @symbol = symbol
      @venue = venue
    end

    def get_quote
      HTTParty.get("#{BASE_URL}/venues/#{@venue}/stocks/#{@symbol}/quote", auth_header).parsed_response
    end

    def place_order(price:, quantity:, direction:, order_type:)
      order = {
        "account" => @account,
        "venue" => @venue,
        "symbol" => @symbol,
        "price" => price,
        "qty" => quantity,
        "direction" => direction,
        "orderType" => order_type
      }

      HTTParty.post("#{BASE_URL}/venues/#{@venue}/stocks/#{@symbol}/orders", body: JSON.dump(order),
      headers: auth_header).parsed_response
    end

    def cancel_order(order_id)
      HTTParty.delete("#{BASE_URL}/venues/#{@venue}/stocks/#{@symbol}/orders/#{order_id}", headers: auth_header)
    end

    def order_status(order_id)
      HTTParty.get("#{BASE_URL}/venues/#{@venue}/stocks/#{@symbol}/orders/#{order_id}", headers: auth_header).parsed_response
    end

    def order_book
      HTTParty.get("#{BASE_URL}/venues/#{@venue}/stocks/#{@symbol}", headers: auth_header).parsed_response
    end

    def venue_up?
      response = HTTParty.get("#{BASE_URL}/venues/#{@venue}/heartbeat", headers: auth_header).parsed_response
      response["ok"]
    end

    def status_all
      HTTParty.get("#{BASE_URL}/venues/#{@venue}/accounts/#{@account}/orders", headers: auth_header)
    end

    def auth_header
      {"X-Starfighter-Authorization" => @api_key}
    end

    private :auth_header

  end
end

class ChockToBlock
  def initialize(account:, venue:, stock:)
    @account = account
    @venue = venue
    @stock = stock
    @api = Stockfighter::API.new(
      key: ENV["STOCKFIGHTER_API_KEY"],
      account: account,
      venue: venue,
      symbol: stock
    )
  end

  def run_level
    quantity_remaining = 100_000

    return unless @api.venue_up?

    while @api.venue_up? && quantity_remaining > 0
      quote = _get_and_print_quote
      price_to_bid = _price_to_bid(quote)
      quantity_to_bid = _quantity_to_bid(quantity_remaining)
      current_order = _place_order(price_to_bid, quantity_to_bid, quote)

      sleep(2)

      order_status = _get_order_status(current_order["id"])

      # kill and re-bid if not filled
      if order_status["open"]
        7.times do
          sleep(3)
          # compare old and new to decide whether or not to place new order
          order_status = _get_order_status(current_order["id"])
          if !order_status["open"]
            quantity_remaining -= current_order["originalQty"]
            puts "Filled order #{current_order["id"]} for #{current_order["totalFilled"]} out of #{current_order["originalQty"]}. Shares remaining to buy: #{quantity_remaining}"
            break
          end
        end

        order_status = _get_order_status(current_order["id"])
        if order_status["open"]
          cancelled_order = @api.cancel_order(current_order["id"])
          quantity_remaining -= cancelled_order["totalFilled"]
          puts "Cancelled order #{current_order["id"]}. Filled #{cancelled_order["totalFilled"]} out of #{cancelled_order["originalQty"]}. Shares remaining to buy: #{quantity_remaining}"
        else
          quantity_remaining -= current_order["originalQty"]
          puts "Filled order #{current_order["id"]} for #{current_order["totalFilled"]} out of #{current_order["originalQty"]}. Shares remaining to buy: #{quantity_remaining}"
        end
      else
        quantity_remaining -= current_order["originalQty"]
        puts "Filled order #{current_order["id"]} for #{current_order["totalFilled"]} out of #{current_order["originalQty"]}. Shares remaining to buy: #{quantity_remaining}"
      end

      sleep(1.5)
    end
  end

  def _get_and_print_quote
    quote = @api.get_quote
    puts "Quote: bid at $#{quote["bid"]}, ask at $#{quote["ask"]}"
    quote["bid"] ||= quote["last"]
    quote
  end

  def _place_order(price, quantity, quote)
    order = @api.place_order(price: price, quantity: quantity, direction: "buy", order_type: "limit")
    puts "Placed order #{order["id"]} for #{quantity} shares at price $#{price}. Quote bid: #{quote["bid"]}, quote last: #{quote["last"]}"
    order
  end

  def _get_order_status(order_id)
    order_status = @api.order_status(order_id)
    puts "Status for order #{order_id}: filled #{order_status["totalFilled"]} out of #{order_status["originalQty"]} at $#{order_status["price"]}"
    order_status
  end

  def _price_to_bid(quote)
    quote["bid"] - 5
  end

  def _quantity_to_bid(quantity_remaining)
    quantity_remaining < 5000 ? quantity_remaining : rand(500..5000)
  end
end

ChockToBlock.new(
  account: "FRB46350645",
  venue: "EUZOEX",
  stock: "SMH"
).run_level
