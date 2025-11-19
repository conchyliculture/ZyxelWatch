require 'sinatra'
require 'prometheus/client'

require_relative 'client'

client = XGS1210Api.new(ENV['ZYXEL_HOST'], ENV['QvTIjLJIjQ1M836']) 

prometheus = Prometheus::Client.registry

ports_info = client.get_ports_info()
ports_info.each_key do |port|
  prometheus.gauge(
    "port_#{port}_rx_packets".to_sym,
    docstring: "Total number of packets processed by port #{port}",
    labels: [:device]
  ) do
    set(client.ports_info[port]['rx_packets'], labels: { device: 'Toto' })
  end
end

set :bind, '0.0.0.0'

use Rack::Deflater
use Prometheus::Client::Rack::Exporter
