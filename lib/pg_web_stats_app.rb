require 'sinatra'
require 'pg_web_stats'

class PgWebStatsApp < Sinatra::Base
  set :root,  File.expand_path(File.join(File.dirname(__FILE__), '../'))
  set :views, File.join(settings.root, 'views')

  helpers do
    def sort_link(title, key, alt_title = nil)
      direction = if params[:order_by] == key && params[:direction] == "desc"
        "asc"
      else
        "desc"
      end

      url = "?order_by=#{key}&direction=#{direction}"
      url += "&userid=#{params[:userid]}" if params[:userid]
      url += "&dbid=#{params[:dbid]}" if params[:dbid]
      url += "&mintime=#{params[:mintime]}" if params[:mintime]
      url += "&mincalls=#{params[:mincalls]}" if params[:mincalls]
      url += "&q=#{params[:q]}" if params[:q]

      "<a href='#{url}' title='#{alt_title}'>#{title}</a>"
    end

    def sanatize_str(str)
      str.to_s.gsub('"', '&quot;')
    end
  end

  get '/healthy' do
    PG_WEB_STATS.get_stats(
      order: 'mean_time desc',
      userid: '16388',
      dbid: '16403',
      q: 'SELECT',
      mincalls: 999999,
      mintime: 999999
    )
    'OK'
  end

  get '/' do
    order_by = if params[:order_by] && params[:direction]
      "#{params[:order_by]} #{params[:direction]}"
    else
      "mean_time desc"
    end

    params[:mincalls] = "0" if params[:mincalls] == ""
    params[:mintime] = "0" if params[:mintime] == ""

    begin
      params[:mincalls] = Rack::Utils.escape_html(params[:mincalls])
      params[:mincalls] = Integer(params[:mincalls], 10)
    rescue ArgumentError
      params[:mincalls] = "0"
    end

    begin
      params[:mintime] = Rack::Utils.escape_html(params[:mintime])
      params[:mintime] = Integer(params[:mintime], 10)
    rescue ArgumentError
      params[:mintime] = "0"
    end


    @stats = PG_WEB_STATS.get_stats(
      order: order_by,
      userid: params[:userid],
      dbid: params[:dbid],
      q: params[:q],
      mincalls: params[:mincalls],
      mintime: params[:mintime]
    )

    @databases = PG_WEB_STATS.databases
    @users = PG_WEB_STATS.users

    erb :queries, layout: :application
  end
end
