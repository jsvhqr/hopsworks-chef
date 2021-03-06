include_recipe "hops::wrap"

case node.platform
when "ubuntu"
 if node.platform_version.to_f <= 14.04
   node.override.hopsworks.systemd = "false"
 end
end

if node.hopsworks.systemd === "true" 
  systemd = true
else
  systemd = false
end


##
## default.rb
##

# If the install.rb recipe was in a different run, the location of the install dir may
# not be correct. install_dir is updated by install.rb, but not persisted, so we need to
# reset it
if node.glassfish.install_dir.include?("versions") == false
  node.override.glassfish.install_dir = "#{node.glassfish.install_dir}/glassfish/versions/current"
end

domains_dir = node.glassfish.domains_dir
private_ip=my_private_ip()
hopsworks_db = "hopsworks"
realmname="kthfsrealm"
#mysql_user=node.mysql.user
#mysql_pwd=node.mysql.password


begin
  elastic_ip = private_recipe_ip("elastic","default")
rescue 
  elastic_ip = ""
  Chef::Log.warn "could not find the elastic server ip for HopsWorks!"
end

begin
  spark_history_server_ip = private_recipe_ip("hadoop_spark","historyserver")
rescue 
  spark_history_server_ip = node.hostname
  Chef::Log.warn "could not find the spark history server ip for HopsWorks!"
end

begin
  oozie_ip = private_recipe_ip("oozie","default")
rescue 
  oozie_ip = node.hostname
  Chef::Log.warn "could not find oozie ip for HopsWorks!"
end

begin
  jhs_ip = private_recipe_ip("apache_hadoop","jhs")
rescue 
  jhs_ip = node.hostname
  Chef::Log.warn "could not find the MR job history server ip!"
end

begin
  livy_ip = private_recipe_ip("livy","default")
rescue 
  livy_ip = node.hostname
  Chef::Log.warn "could not find livy server ip!"
end

begin
  epipe_ip = private_recipe_ip("epipe","default")
rescue 
  epipe_ip = node.hostname
  Chef::Log.warn "could not find th epipe server ip!"
end

begin
  zk_ip = private_recipe_ip("kzookeeper","default")
rescue 
  zk_ip = node.hostname
  Chef::Log.warn "could not find th zk server ip!"
end

begin
  kafka_ip = private_recipe_ip("kkafka","default")
rescue 
  kafka_ip = node.hostname
  Chef::Log.warn "could not find th kafka server ip!"
end



tables_path = "#{domains_dir}/tables.sql"
rows_path = "#{domains_dir}/rows.sql"

hopsworks_grants "hopsworks_tables" do
  tables_path  "#{tables_path}"
  rows_path  "#{rows_path}"
  action :nothing
end 

Chef::Log.info("Could not find previously defined #{tables_path} resource")
template tables_path do
  source File.basename("#{tables_path}") + ".erb"
  owner node.glassfish.user
  mode 0750
  action :create
  variables({
                :private_ip => private_ip
              })
    notifies :create_tables, 'hopsworks_grants[hopsworks_tables]', :immediately
end 

timerTable = "ejbtimer_mysql.sql"
timerTablePath = "#{Chef::Config.file_cache_path}/#{timerTable}"

hopsworks_grants "timers_tables" do
  tables_path  "#{timerTablePath}"
  rows_path  ""
  action :nothing
end 


template timerTablePath do
  source File.basename("#{timerTablePath}") + ".erb"
  owner "root"
  mode 0750
  action :create
  notifies :create_timers, 'hopsworks_grants[timers_tables]', :immediately
end 



template "#{rows_path}" do
   source File.basename("#{rows_path}") + ".erb"
   owner node.glassfish.user
   mode 0755
   action :create
    variables({
                :epipe_ip => epipe_ip,
                :livy_ip => livy_ip,
                :jhs_ip => jhs_ip,
                :oozie_ip => oozie_ip,
                :spark_history_server_ip => spark_history_server_ip,
                :elastic_ip => elastic_ip,
                :spark_dir => node.hadoop_spark.dir + "/spark",                
                :spark_user => node.hadoop_spark.user,
                :hadoop_dir => node.apache_hadoop.dir + "/hadoop",                                
                :yarn_user => node.apache_hadoop.yarn.user,
                :hdfs_user => node.apache_hadoop.hdfs.user,
                :mr_user => node.apache_hadoop.mr.user,
                :flink_dir => node.flink.dir + "/flink",
                :flink_user => node.flink.user,
                :zeppelin_dir => node.zeppelin.dir + "/zeppelin",
                :zeppelin_user => node.zeppelin.user,
                :ndb_dir => node.ndb.dir + "/mysql-cluster",
                :mysql_dir => node.mysql.dir + "/mysql",
                :elastic_dir => node.elastic.dir + "/elastic",
                :twofactor_auth => node.hopsworks.twofactor_auth,
                :elastic_user => node.elastic.user,
                :yarn_default_quota => node.hopsworks.yarn_default_quota_mins.to_i * 60,
                :hdfs_default_quota => node.hopsworks.hdfs_default_quota_gbs.to_i * 1024 * 1024 * 1024,
                :max_num_proj_per_user => node.hopsworks.max_num_proj_per_user,
                :zk_ip => zk_ip,
                :kafka_ip => kafka_ip,                
                :kafka_num_replicas => node.hopsworks.kafka_num_replicas,
                :kafka_num_partitions => node.hopsworks.kafka_num_partitions,
                :kafka_user => node.kkafka.user
              })
   notifies :insert_rows, 'hopsworks_grants[hopsworks_tables]', :immediately
end



###############################################################################
# config glassfish
###############################################################################

username=node.hopsworks.admin.user
password=node.hopsworks.admin.password
domain_name="domain1"
admin_port = 4848
mysql_host = private_recipe_ip("ndb","mysqld")


jndiDB = "jdbc/hopsworks"
timerDB = "jdbc/hopsworksTimers"

asadmin = "#{node.glassfish.base_dir}/versions/current/bin/asadmin"
admin_pwd="#{domains_dir}/#{domain_name}_admin_passwd"

password_file = "#{domains_dir}/#{domain_name}_admin_passwd"

login_cnf="#{domains_dir}/#{domain_name}/config/login.conf"
file "#{login_cnf}" do
   action :delete
end

template "#{login_cnf}" do
  cookbook 'hopsworks'
  source "login.conf.erb"
  owner node.glassfish.user
  group node.glassfish.group
  mode "0600"
end


hopsworks_grants "reload_sysv" do
 tables_path  ""
 rows_path  ""
 action :reload_sysv
end 


#case node.platform
# when "debian"

glassfish_secure_admin domain_name do
  domain_name domain_name
  password_file "#{domains_dir}/#{domain_name}_admin_passwd"
  username username
  admin_port admin_port
  secure false
  action :enable
end


#end



props =  { 
  'datasource-jndi' => jndiDB,
  'password-column' => 'password',
  'group-table' => 'hopsworks.users_groups',
  'user-table' => 'hopsworks.users',
  'group-name-column' => 'group_name',
  'user-name-column' => 'email',
  'group-table-user-name-column' => 'email',
  'encoding' => 'Hex',
  'digestrealm-password-enc-algorithm' => 'SHA-256',
  'digest-algorithm' => 'SHA-256'
}

 glassfish_auth_realm "#{realmname}" do 
   realm_name "#{realmname}"
   jaas_context "jdbcRealm"
   properties props
   domain_name domain_name
   password_file "#{domains_dir}/#{domain_name}_admin_passwd"
   username username
   admin_port admin_port
   secure false
   classname "com.sun.enterprise.security.auth.realm.jdbc.JDBCRealm"
 end

 
 cProps = {
     'datasource-jndi' => jndiDB,
     'password-column' => 'password',
     'encoding' => 'Hex',
     'group-table' => 'hopsworks.users_groups',
     'user-table' => 'hopsworks.users',
     'group-name-column' => 'group_name',
     'user-name-column' => 'email',
     'group-table-user-name-column' => 'email',
     'otp-secret-column' => 'secret',
     'user-status-column' => 'status',
     'yubikey-table' => 'hopsworks.yubikey',
     'variables-table' => 'hopsworks.variables'
 }
 
 glassfish_auth_realm "cauthRealm" do 
   realm_name "cauthRealm"
   jaas_context "cauthRealm"
   properties cProps
   domain_name domain_name
   password_file "#{domains_dir}/#{domain_name}_admin_passwd"
   username username
   admin_port admin_port
   secure false
   classname "se.kth.bbc.crealm.CustomAuthRealm"
 end

 

glassfish_asadmin "set server-config.security-service.default-realm=cauthRealm" do
   domain_name domain_name
   password_file "#{domains_dir}/#{domain_name}_admin_passwd"
   username username
   admin_port admin_port
   secure false
end


# Jobs in Hopsworks use the Timer service
glassfish_asadmin "set server-config.ejb-container.ejb-timer-service.timer-datasource=#{timerDB}" do
   domain_name domain_name
   password_file "#{domains_dir}/#{domain_name}_admin_passwd"
   username username
   admin_port admin_port
   secure false
end

glassfish_asadmin "set server.http-service.virtual-server.server.property.send-error_1=\"code=404 path=#{domains_dir}/#{domain_name}/docroot/404.html reason=Resource_not_found\"" do
   domain_name domain_name
   password_file "#{domains_dir}/#{domain_name}_admin_passwd"
   username username
   admin_port admin_port
   secure false
end

# Disable SSLv3 on http-listener-2
glassfish_asadmin "set server.network-config.protocols.protocol.http-listener-2.ssl.ssl3-enabled=false" do
   domain_name domain_name
   password_file "#{domains_dir}/#{domain_name}_admin_passwd"
   username username
   admin_port admin_port
   secure false
end

# Disable SSLv3 on http-adminListener
glassfish_asadmin "set server.network-config.protocols.protocol.sec-admin-listener.ssl.ssl3-enabled=false" do
   domain_name domain_name
   password_file "#{domains_dir}/#{domain_name}_admin_passwd"
   username username
   admin_port admin_port
   secure false
end

# Disable SSLv3 on iiop-listener.ssl
glassfish_asadmin "set server.iiop-service.iiop-listener.SSL.ssl.ssl3-enabled=false" do
   domain_name domain_name
   password_file "#{domains_dir}/#{domain_name}_admin_passwd"
   username username
   admin_port admin_port
   secure false
end

# Disable SSLv3 on iiop-muth_listener.ssl
glassfish_asadmin "set server.iiop-service.iiop-listener.SSL_MUTUALAUTH.ssl.ssl3-enabled=false" do
   domain_name domain_name
   password_file "#{domains_dir}/#{domain_name}_admin_passwd"
   username username
   admin_port admin_port
   secure false
end

# Restrict ciphersuite
glassfish_asadmin "set 'configs.config.server-config.network-config.protocols.protocol.http-listener-2.ssl.ssl3-tls-ciphers=#{node.glassfish.ciphersuite}'" do
   domain_name domain_name
   password_file "#{domains_dir}/#{domain_name}_admin_passwd"
   username username
   admin_port admin_port
   secure false
end

# Restrict ciphersuite
glassfish_asadmin "set 'configs.config.server-config.network-config.protocols.protocol.sec-admin-listener.ssl.ssl3-tls-ciphers=#{node.glassfish.ciphersuite}'" do
   domain_name domain_name
   password_file "#{domains_dir}/#{domain_name}_admin_passwd"
   username username
   admin_port admin_port
   secure false
end

# Restrict ciphersuite
glassfish_asadmin "set 'configs.config.server-config.iiop-service.iiop-listener.SSL_MUTUALAUTH.ssl.ssl3-tls-ciphers=#{node.glassfish.ciphersuite}'" do
   domain_name domain_name
   password_file "#{domains_dir}/#{domain_name}_admin_passwd"
   username username
   admin_port admin_port
   secure false
end

# cluster="hopsworks"

# glassfish_asadmin "create-cluster #{cluster}" do
#    domain_name domain_name
#    password_file "#{domains_dir}/#{domain_name}_admin_passwd"
#    username username
#    admin_port admin_port
#    secure false
# end

# glassfish_asadmin "#asadmin --host das_host --port das_port create-local-instance --node #{hostname} instance_#{hostname}" do
#    domain_name domain_name
#    password_file "#{domains_dir}/#{domain_name}_admin_passwd"
#    username username
#    admin_port admin_port
#    secure false
# end


# glassfish_asadmin "create-local-instance --cluster #{cluster} instance1" do
#    domain_name domain_name
#    password_file "#{domains_dir}/#{domain_name}_admin_passwd"
#    username username
#    admin_port admin_port
#    secure false
# end


# TODO - set ejb timer source as a cluster called 'hopsworks'
# https://docs.oracle.com/cd/E18930_01/html/821-2418/beahw.html#gktqo
# glassfish_asadmin "set configs.config.hopsworks-config.ejb-container.ejb-timer-service.timer-datasource=#{timerDB}" do
#    domain_name domain_name
#    password_file "#{domains_dir}/#{domain_name}_admin_passwd"
#    username username
#    admin_port admin_port
#    secure false
# end


if node.hopsworks.gmail.password .eql? "password"

  bash 'gmail' do
    user "root"
    code <<-EOF
      cd /tmp
      rm -f /tmp/hopsworks.email 
      wget #{node.hopsworks.gmail.placeholder} 
      cat /tmp/hopsworks.email | base64 -d > /tmp/hopsworks.encoded
      chmod 775 /tmp/hopsworks.encoded
    EOF
  end

end



hopsworks_mail "gmail" do
   domain_name domain_name
   password_file "#{domains_dir}/#{domain_name}_admin_passwd"
   username username
   admin_port admin_port
   action :jndi
end 




glassfish_deployable "hopsworks" do
  component_name "hopsworks"
  url node.hopsworks.war_url
  context_root "/hopsworks"
  domain_name domain_name
  password_file "#{domains_dir}/#{domain_name}_admin_passwd"
  username username
  admin_port admin_port
  secure false
  action :deploy
  async_replication false
  retries 2
  not_if "#{asadmin} --user #{username} --passwordfile #{admin_pwd}  list-applications --type ejb | grep -w 'hopsworks'"
end




# directory "/srv/users" do
#   owner node.glassfish.user

#   group node.glassfish.group
#   mode "0755"
#   action :create
#   recursive true
# end


# template "/srv/mkuser.sh" do
# case node['platform']
# when 'debian', 'ubuntu'
#     source "mkuser.sh.erb"
# when 'redhat', 'centos', 'fedora'
#     source "mkuser.redhat.sh.erb"
# end
#   owner node.glassfish.user
#   mode 0750
#   action :create
# end 
 template "/bin/hopsworks-2fa" do
    source "hopsworks-2fa.erb"
    owner "root"
    mode 0700
    action :create
 end 


