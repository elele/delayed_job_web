require 'sinatra/base'
require 'active_support'
require 'active_record'
require 'delayed_job'
require 'haml'

class DelayedJobWeb < Sinatra::Base
  set :root, File.dirname(__FILE__)
  set :static, true
  set :public_folder,  File.expand_path('../public', __FILE__)
  set :views,  File.expand_path('../views', __FILE__)
  set :haml, { :format => :html5 }

  def current_page
    url_path request.path_info.sub('/','')
  end

  def start
    params[:start].to_i
  end

  def per_page
    20
  end

  def url_path(*path_parts)
    [ path_prefix, path_parts ].join("/").squeeze('/')
  end
  alias_method :u, :url_path

  def path_prefix
    request.env['SCRIPT_NAME']
  end

  def tabs
    [
      {:name => 'Overview', :path => '/overview'},
      {:name => 'Enqueued', :path => '/enqueued'},
      {:name => 'Working', :path => '/working'},
      {:name => 'Scheduled', :path => '/scheduled'},
      {:name => 'Failed', :path => '/failed'}
    ]
  end

  def delayed_job
    begin
      Delayed::Job
    rescue
      false
    end
  end

  get '/overview' do
    if delayed_job
      haml :overview
    else
      @message = "Unable to connected to Delayed::Job database"
      haml :error
    end
  end

  %w(enqueued working scheduled failed).each do |page|
    get "/#{page}" do
      @jobs = delayed_jobs(page.to_sym).order('updated_at DESC').offset(start).limit(per_page)
      @all_jobs = delayed_jobs(page.to_sym)
      haml page.to_sym
    end
  end

  get "/delete/:id" do
    delayed_job.find(params[:id]).delete
    redirect back
  end

  get "/reload/:id" do
    job = delayed_job.find(params[:id])
    job.run_at = Time.now
    job.failed_at = nil
    job.locked_by = nil
    job.locked_at = nil
    job.attempts = 0
    job.last_error = nil
    job.save!
    redirect back
  end

  post "/failed/reload" do
    delayed_jobs(:failed).update_all(
      :run_at => Time.now,
      :failed_at => nil,
      :locked_by => nil,
      :locked_at => nil,
      :attempts => 0,
      :last_error => nil
    )
    redirect back
  end

  post "/failed/delete" do
    delayed_jobs(:failed).delete_all
    redirect u('failed')
  end

  def delayed_jobs(type)
    delayed_job.where(delayed_job_sql(type))
  end

  def delayed_job_sql(type)
    case type
    when :enqueued
      'locked_at IS NULL AND failed_at IS NULL AND (run_at IS NULL OR run_at <= now())'
    when :working
      'locked_at IS NOT NULL AND failed_at IS NULL'
    when :failed
      'failed_at IS NOT NULL'
    when :scheduled
      'locked_at IS NULL AND failed_at IS NULL AND run_at > now()'
    end
  end

  get "/?" do
    redirect u(:overview)
  end

  def partial(template, local_vars = {})
    @partial = true
    haml(template.to_sym, {:layout => false}, local_vars)
  ensure
    @partial = false
  end

  %w(overview enqueued working scheduled failed) .each do |page|
    get "/#{page}.poll" do
      show_for_polling(page)
    end

    get "/#{page}/:id.poll" do
      show_for_polling(page)
    end
  end

  def poll
    if @polling
      text = "Last Updated: #{Time.now.strftime("%H:%M:%S")}"
    else
      text = "<a href='#{u(request.path_info)}.poll' rel='poll'>Live Poll</a>"
    end
    "<p class='poll'>#{text}</p>"
  end

  def show_for_polling(page)
    content_type "text/html"
    @polling = true
    # show(page.to_sym, false).gsub(/\s{1,}/, ' ')
    @jobs = delayed_jobs(page.to_sym)
    haml(page.to_sym, {:layout => false})
  end

end

# Run the app!
#
# puts "Hello, you're running delayed_job_web"
# DelayedJobWeb.run!
