module Lita
  module Handlers
    class JenkinsNotifier < Handler
      def initialize(robot)
        super(robot)
        @job_statuses = {}
      end

      config :jobs, default: {}

      http.post '/jenkins/notifications', :build_notification

      def build_notification(request, _response)
        json_stuff = request.body
        begin
          payload = MultiJson.load(json_stuff, symbolize_keys: true)
        rescue MultiJson::LoadError => e
          Lita.logger.error("Could not parse JSON payload from jenkins: #{e.message}")
          Lita.logger.debug('JSON PAYLOAD: ' + json_stuff)
          return
        end
        rooms = get_rooms(payload[:name])

        message = create_message(payload)
        rooms.each do |room|
          target = Source.new(room: room)
          robot.send_message(target, message)
        end
      end

      private

      def create_message(payload)
        name = payload[:name]
        build = payload[:build]

        phase = build[:phase]
        number = build[:number]
        status = build[:status]
        branch = build[:scm][:branch]
        full_url = build[:full_url]

        if phase == 'STARTED'
          "[Jenkins] Build ##{number} started for #{name} on #{branch}: #{full_url}"
        elsif phase == 'COMPLETED' || phase == 'FINISHED'
          if @job_statuses[name] == status
            phrase = if status == 'SUCCESS'
                       'SUCCESSFUL'
                     elsif status == 'FAILURE'
                       'FAILING'
                     elsif status == 'NOT_BUILT'
                       'NOT BUILT'
                     end
            "[Jenkins] [STILL #{phrase}] Build ##{number} Completed for #{name} on #{branch}: #{full_url}"
          else
            @job_statuses[name] = status
            "[Jenkins] [#{status}] Build ##{number} Completed for #{name} on #{branch}: #{full_url}"
          end
        end
      end

      def get_rooms(job_name)
        jobs = Lita.config.handlers.jenkins_notifier.jobs

        rooms = []
        jobs.keys.each do |key|
          rooms << jobs[key] if key.match(job_name)
        end

        if rooms.empty?
          Lita.logger.warn "Jenkins notification for job that didn't match any: #{job_name}"
        end

        rooms.sort.uniq
      end
    end

    Lita.register_handler(JenkinsNotifier)
  end
end
