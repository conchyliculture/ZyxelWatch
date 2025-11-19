require "digest"
require "json"
require 'logger'

require "mechanize"
require "openssl"
require "pry"

def gen_csrf
  return Digest::MD5.hexdigest(Time.now.to_s)[0..15]
end

class XGS1210Api
  PORT_TYPES = {
    0 => "Ethernet",
    1 => "FastEthernet",
    2 => "GigabitEthernet",
    3 => "TwoPointFiveGigabitEthernet",
    4 => "FiveGigabitEthernet",
    6 => "TenGigabitEthernet"
  }.freeze

  def initialize(host, password)
    raise StandardError, "Need a password" unless password
    raise StandardError, "Need a host" unless host

    @switch_url = host
    @password = password

    @mechanize = Mechanize.new(host)
    @mechanize.agent.http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    @logged_in = false
    @csrf = gen_csrf()
  end

  def login
    return if @logged_in

    # WTF is that Hash
    json = { "_ds=1&password=#{@password}&xsrfToken=#{@csrf}&_de=1" => {} }.to_json
    data = JSON.parse(_cgi_set("home_loginAuth", data: json))
    raise StandardError, "Could not login, check password" unless data['status'] == "ok"

    auth_id = data['authId']
    json = { "_ds=1&authId=#{auth_id}&xsrfToken=#{@csrf}&_de=1" => {} }.to_json
    data = JSON.parse(_cgi_set("home_loginStatus", data: json))
    raise StandardError, "Could not login, check password" unless data['data']['status'] == "ok"

    @logged_in = true
  end

  def _build_cgi_uri(method, cmd, params)
    uri = URI.parse("#{@switch_url}/cgi/#{method}.cgi?cmd=#{cmd}")

    unless params['dummy']
      params['dummy'] = (Time.now.to_f * 1000).to_i
    end

    unless params['bj4']
      q = "#{uri.query}&#{URI.encode_www_form(params)}"
      params['bj4'] = Digest::MD5.hexdigest(q)
    end

    uri.query = "#{uri.query}&#{URI.encode_www_form(params)}"
    return uri
  end

  def _cgi_set(cmd, data: nil, params: {})
    res = @mechanize.post(_build_cgi_uri('set', cmd, params), data, { 'Content-Type' => 'application/json' })

    return res.body
  end

  def _cgi_get(cmd, params: {})
    res = @mechanize.get(_build_cgi_uri('get', cmd, params))

    return res.body
  end

  def get_info
    loop do
      break if @logged_in

      login
    end
    data = JSON.parse(_cgi_get('home_main'))['data']
    return data
  end

  def get_ports_info()
    loop do
      break if @logged_in

      login
    end
    num_ports = JSON.parse(_cgi_get('home_main'))['data']['max_port']
    ports_data = JSON.parse(_cgi_get('port_portInfo'))['data']
    links_data = JSON.parse(_cgi_get('home_linkData'))['data']
    ports_info = {}
    1.upto(num_ports.to_i) do |port|
      ports_info[port] = {
        'index': port,
        'max_speed': PORT_TYPES[ports_data['portType'][port]],
        'name': ports_data['portType'][port],
        'physical': ports_data['isCopper'][port] == 1 ? 'copper' : 'fibre',
        'enabled': ((ports_data["portState"] >> port) & 1) == 1,
        'status': links_data['portstatus'][port],
        'speed': links_data['speed'][port],
        'rx_packets': links_data['stats'][port][0],
        'tx_packets': links_data['stats'][port][1],
        'crc_errors': links_data['stats'][port][2]
      }
    end

    return ports_info
  end
end

#puts client.get_ports_info
