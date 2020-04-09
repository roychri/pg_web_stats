require 'pg'
require 'coderay'
require 'yaml'

class PgWebStats
  attr_accessor :connection

  def initialize()
    self.connect()
  end

  def connect()
    self.connection = PG.connect(
      dbname: ENV["POSTGRES_DB_NAME"],
      host: ENV["POSTGRES_DB_HOST"],
      user: ENV["POSTGRES_DB_USER"],
      password: ENV["POSTGRES_DB_PASSWORD"],
      port: ENV["POSTGRES_DB_PORT"]
    )
  end

  def exec_query( query )
    begin
      return connection.exec( query ) do | results |
        yield results
      end
    rescue PG::UnableToSend
      connect()
    end
  end

  def get_stats(params = { order: "mean_time desc" })
    query = build_stats_query(params)

    results = []
    exec_query(query) do |result|
      result.each do |row|
        results << Row.new(row, users, databases)
      end
    end

    results
  end

  def users
    @users ||= select_by_oid("select oid, rolname from pg_authid order by rolname;", 'rolname')
  rescue PG::InsufficientPrivilege
    @users ||= select_by_oid("select distinct usesysid oid, usename rolname from pg_user inner join pg_stat_statements on userid = usesysid where query NOT LIKE '%insufficient privilege%';", 'rolname')
  end

  def databases
    @databases ||= select_by_oid("select pg_database.oid, datname from pg_database inner join pg_stat_statements on dbid=pg_database.oid AND query NOT LIKE '%insufficient privilege%' order by datname;", 'datname')
  end

  private

  def select_by_oid(select_query, row_name)
    @selection = {}
    exec_query(select_query) do |result|
      result.each do |row|
        @selection[row['oid']] = row[row_name]
      end
    end

    @selection
  end

  def build_stats_query(params)
    order_by = params[:order]

    query = "SELECT * FROM pg_stat_statements"

    where_conditions = []

    userid = params[:userid]
    if userid && !userid.empty?
      where_conditions << "userid='#{connection.escape_string(userid)}'"
    else
      where_conditions << "userid IN (#{users.keys.join(',')})"
    end

    dbid = params[:dbid]
    if dbid && !dbid.empty?
      where_conditions << "dbid='#{connection.escape_string(dbid)}'"
    end

    q = params[:q]
    if q && !q.empty?
      where_conditions << "query LIKE '#{connection.escape_string(q)}%'"
    end

    if params[:mincalls]
      where_conditions << "calls > #{params[:mincalls]}"
    end

    if params[:mintime]
      where_conditions << "mean_time > #{params[:mintime]}"
    end

    query += " WHERE #{where_conditions.join(" AND ")}" if where_conditions.size > 0

    query += " ORDER BY #{order_by}"

    query
  end
end

class PgWebStats::Row
  attr_accessor :data, :users, :databases

  def initialize(data, users, databases)
    self.data = data
    self.users = users
    self.databases = databases
  end

  def respond_to?(method_sym, include_private = false)
    if data[method_sym.to_s]
      true
    else
      super
    end
  end

  def method_missing(method_sym, *arguments, &block)
    if result = data[method_sym.to_s]
      result
    else
      super
    end
  end

  def user
    users[userid]
  end

  def db
    databases[dbid]
  end

  def query
    CodeRay.scan(data["query"].gsub(/\s+/, ' ').strip, "sql").div(:css => :class)
  end

  def waste?
    clean_query = self.query.dup.downcase.strip
    keywords = ['show', 'set', 'rollback', 'savepoint', 'release', 'begin', 'create_extension']
    keywords.any? { |k| clean_query.start_with?(k) }
  end
end
