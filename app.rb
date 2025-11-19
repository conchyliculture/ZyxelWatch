require 'sinatra'
require 'prometheus/client'
require 'prometheus/middleware/exporter'

require_relative 'client'

# Fuck this shit
module Rack
  class Lint
    def call(env = nil)
      @app.call(env)
    end
  end
end

prometheus = Prometheus::Client.registry

PACKETS_RX = prometheus.gauge(
  :client_port_packets_received_total,
  docstring: 'Total packets received on a client port',
  labels: [:port]
)

PACKETS_TX = prometheus.gauge(
  :client_port_packets_transmitted_total,
  docstring: 'Total packets transmitted from a client port',
  labels: [:port]
)

client = XGS1210Api.new(ENV['ZYXEL_HOST'], ENV['ZYXEL_PASSWORD'])

prometheus.collect do
  ports_info = client.get_ports_info()

  ports_info.each_key do |port|
    PACKETS_RX.set(ports_info[port][:rx_packets], labels: { port: "Port_#{port}" })

    # Set the value for the TX gauge for this specific port
    PACKETS_TX.set(ports_info[port][:tx_packets], labels: { port: "Port #{port}" })
  end
end

set :bind, '0.0.0.0'

use Rack::Deflater
use Prometheus::Middleware::Exporter, registry: prometheus
