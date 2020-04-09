require 'sinatra'
require 'sinatra/param'
require 'pg_web_stats'

class PgWebStatsApp < Sinatra::Base
  helpers Sinatra::Param

  set :root,  File.expand_path(File.join(File.dirname(__FILE__), '../'))
  set :views, File.join(settings.root, 'views')

  helpers do
    def link(title, update, alt_title = nil)
      update = Hash[update.map{ |k, v| [k.to_s, v] }]
      url = "?" + URI.encode_www_form(params.merge(update))

      "<a href='#{url}' title='#{alt_title}'>#{title}</a>"
    end

    def page_links
      offset = params[:offset]
      count = params[:count]

      pages = @stats[:total].fdiv(count).floor  # Pages are 0-indexed, so floor
      this_page = offset.fdiv(count).floor

      Enumerator.new do |enum|
        if offset > 0
          enum.yield text: 'prev', offset: [0, offset - count].max
        end

        [0, this_page - 4].max.upto([this_page + 4, pages].min) do |page|
          classname = page == this_page ? "active" : ""
          enum.yield text: (page + 1).to_s, offset: page * count, class: classname
        end

        if @stats[:items].length >= count
          enum.yield text: 'next', offset: offset + count
        end
      end
    end

    def sort_link(title, update, alt_title = nil)
      direction = if params[:order_by] == update && params[:direction] == "desc"
                    "asc"
                  else
                    "desc"
                  end
      update = {
        order_by: update,
        direction: direction,
        offset: 0   # Changing sorting resets pagination
      }
      link title, update, alt_title
    end

    def page_link(info)
      text = info.delete(:text)
      classname = info.delete(:class)
      attrs = classname && !classname.empty? ? " class=\"#{classname}\"" : ""
      "<li#{attrs}>" + link(text, info) + "</li>"
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
    param :q,          String
    param :userid,     String, format: /^\d*$/
    param :dbid,       String, format: /^\d*$/
    param :count,      Integer, default: 25
    param :offset,     Integer, default: 0
    param :order_by,   String, default: "total_time"
    param :direction,  String, in: ["asc", "desc"], default: "desc"

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

    all_keys = %w{q userid dbid count offset order_by direction mincalls mintime}
    params.select {|key| all_keys.include? key}
    @stats = PG_WEB_STATS.get_stats(params)

    @databases = PG_WEB_STATS.databases
    @users = PG_WEB_STATS.users

    erb :queries, layout: :application
  end
end
