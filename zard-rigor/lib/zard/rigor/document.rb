# frozen_string_literal: true

module Zard
  module Rigor
    class Document
      STATUSES = %w[ok not_found not_ruby outside_project duplicate parse_error failed].freeze
      PROVENANCES = %w[sig inline inferred library].freeze

      def initialize(data, root:, selected:, arguments:, status:)
        @data = data
        @root = root
        @selected = selected
        @sites = {}
        @members = {}
        @files = {}
        validate(arguments, status)
      end

      def bind(export, base:, project:)
        bindings = []
        retained = []
        warnings = []
        export.fetch("scopes").each do |scope|
          scope.fetch("declarations").each do |row|
            path = Pathname.new(File.expand_path(row.fetch("span").fetch("path"), base)).relative_path_from(Pathname.new(@root)).to_s
            file = @files.fetch(path)
            candidates = (file["sites"] || []).select { |site| matches?(row, site) }
            binding = {"scope" => scope.fetch("name"), "declaration_id" => row.fetch("id"), "site_key" => nil, "member_keys" => []}
            if candidates.one?
              site = candidates.first
              retained << site.fetch("key")
              binding["site_key"] = site.fetch("key")
              binding["status"] = "matched"
              binding["member_keys"] = @members.filter_map { |key, member| key if member.fetch("sites").include?(site.fetch("key")) }
            else
              binding["status"] = "unavailable"
              binding["reason"] = if file["status"] != "ok"
                file["status"]
              elsif candidates.empty?
                "not_reported"
              else
                "ambiguous_site"
              end
              warnings << "#{scope.fetch("name")}:#{row.fetch("display_name")}: lens #{binding.fetch("reason")}"
            end
            bindings << binding
          end
        end
        used_members = bindings.flat_map { |binding| binding.fetch("member_keys") }.uniq
        retained |= used_members.flat_map { |key| @members.fetch(key).fetch("sites") }
        files = @data.fetch("files").map do |file|
          file.merge("sites" => file["sites"]&.select { |site| retained.include?(site.fetch("key")) })
        end
        members = used_members.map do |key|
          member = @members.fetch(key)
          member.merge("key" => key, "sites" => member.fetch("sites").select { |site| retained.include?(site) })
        end
        @data.merge("adapter" => {"name" => "zard-rigor", "version" => VERSION, "grammar" => "rigor:v1"},
          "project" => project, "files" => files, "members" => members, "bindings" => bindings, "warnings" => warnings)
      end

      private

      def reject!(message)
        raise Error, "Invalid lens/v0 document: #{message}"
      end

      def validate(arguments, status)
        reject!("expected object") unless @data.is_a?(Hash)
        reject!("unsupported schema/revision") unless @data.values_at("schema", "revision") == ["lens/v0", 1]
        producer = @data.fetch("producer")
        reject!("invalid producer") unless producer.is_a?(Hash)
        reject!("expected Rigor 0.4.3") unless producer.values_at("name", "version") == ["rigor", "0.4.3"]
        reject!("invalid context") unless @data.fetch("context").is_a?(Hash)
        capabilities = @data.fetch("capabilities")
        reject!("missing required capabilities") unless capabilities.is_a?(Array) && (%w[class module method attribute] - capabilities).empty?
        files = @data.fetch("files")
        reject!("expected target array") unless files.is_a?(Array) && files.all? { |file| file.is_a?(Hash) }
        reject!("missing, reordered or unexpected targets") unless files.map { |file| file.fetch("argument") } == arguments
        files.each_with_index { |file, i| validate_file(file, @selected.keys.sort.fetch(i)) }
        ok = files.count { |file| file.fetch("status") == "ok" }
        reject!("exit status contradicts targets") unless status == (ok.positive? ? 0 : 1)
        raise Error, "rigor lens produced no successful targets: #{files.map { |file| file["reason"] }.join("; ")}" if ok.zero?

        members = @data.fetch("members")
        reject!("expected member array") unless members.is_a?(Array) && members.all? { |member| member.is_a?(Hash) }
        members.each { |member| validate_member(member) }
      end

      def validate_file(file, absolute)
        status = file.fetch("status")
        reject!("unknown target status") unless STATUSES.include?(status)
        path = Pathname.new(absolute).relative_path_from(Pathname.new(@root)).to_s
        reject!("target path mismatch") if file["path"] && file["path"] != path
        reject!("failed target has no reason") if status != "ok" && !file["reason"].is_a?(String)
        @files[path] = file
        return unless %w[ok parse_error].include?(status)

        expected = "xxh3-64:#{Digest::XXH3_64bits.hexdigest(@selected.fetch(absolute))}"
        reject!("stale source digest for #{path}") unless file.fetch("digest") == expected
        return unless status == "ok"

        reject!("invalid completeness/omissions") unless [true, false].include?(file.fetch("complete")) && file.fetch("omissions").is_a?(Array)
        reject!("completeness contradicts omissions") unless file.fetch("complete") == file.fetch("omissions").empty?
        reject!("expected sites/inputs arrays") unless file.fetch("sites").is_a?(Array) && file.fetch("inputs").is_a?(Array)
        file.fetch("sites").each do |site|
          location = site.fetch("span")
          validate_span(location, @selected.fetch(absolute))
          key = "#{path}:#{location.fetch("start_offset")}-#{location.fetch("end_offset")}:#{site.fetch("ordinal")}"
          reject!("duplicate or invalid site key") if site.fetch("key") != key || @sites.key?(key)
          reject!("unknown site kind") unless %w[class module method attribute].include?(site.fetch("kind"))
          slot(site.fetch("body_return")) if site["body_return"]
          @sites[key] = site
        end
        file.fetch("inputs").each do |input|
          path = input.fetch("path")
          actual = File.realpath(File.expand_path(path, @root))
          reject!("input escapes project root") unless actual.start_with?(@root + File::SEPARATOR)
          reject!("input changed: #{path}") unless "xxh3-64:#{Digest::XXH3_64bits.hexdigest(File.binread(actual))}" == input.fetch("digest")
        end
      end

      def validate_span(span, source)
        first = span.fetch("start_offset")
        last = span.fetch("end_offset")
        reject!("invalid byte span") unless first.is_a?(Integer) && last.is_a?(Integer) && first >= 0 && last > first && last <= source.bytesize
        %w[start end].each do |edge|
          offset = span.fetch("#{edge}_offset")
          prefix = source.byteslice(0, offset)
          line = prefix.count("\n") + 1
          column = offset - ((prefix.b.rindex("\n") || -1) + 1)
          reject!("line/column drift") unless span.values_at("#{edge}_line", "#{edge}_column") == [line, column]
        end
      end

      def validate_member(member)
        reject!("invalid member identity") unless member.fetch("owner").is_a?(String) && member.fetch("name").is_a?(String)
        key = JSON.generate(member.values_at("owner", "scope", "name"))
        reject!("duplicate member") if @members.key?(key)
        reject!("invalid member scope/basis") unless %w[instance singleton].include?(member.fetch("scope")) && %w[contract single_site contested].include?(member.fetch("basis"))
        sites = member.fetch("sites")
        reject!("unknown member site") unless sites.is_a?(Array) && !sites.empty? && sites.uniq == sites && sites.all? { |site| @sites.key?(site) }
        sites.each do |key|
          site = @sites.fetch(key)
          reject!("member ownership mismatch") unless site.values_at("owner", "scope") == member.values_at("owner", "scope") && site.fetch("members").include?(member.fetch("name"))
        end
        overloads = member.fetch("overloads")
        reject!("expected overload array") unless overloads.is_a?(Array)
        reject!("contested member must not assert overloads") if member.fetch("basis") == "contested" && !overloads.empty?
        overloads.each do |overload|
          reject!("invalid RBS text") unless overload["rbs"].nil? || overload["rbs"].is_a?(String)
          values = (overload["params"] || []).map { |parameter| parameter.fetch("type") }
          values << overload.fetch("block").fetch("type") if overload["block"]
          values << overload.fetch("return")
          reject!("unavailable slots cannot assert RBS text") if values.any? { |value| value["state"] == "unavailable" } && overload["rbs"]
          overload["params"]&.each { |parameter| slot(parameter.fetch("type"), member_sites: sites) }
          slot(overload.fetch("block").fetch("type"), member_sites: sites) if overload["block"]
          slot(overload.fetch("return"), member_sites: sites)
        end
        @members[key] = member
      end

      def slot(value, member_sites: [])
        reject!("expected slot object") unless value.is_a?(Hash)
        case value.fetch("state")
        when "unavailable"
          reject!("unknown unavailable reason") unless %w[contested not_computed definition_build_failed].include?(value.fetch("reason"))
        when "typed", "dynamic"
          reject!("missing type text") unless value.fetch("type").is_a?(String)
          provenance = value.fetch("provenance")
          known = provenance.is_a?(String) && (PROVENANCES.include?(provenance) || provenance.match?(/\Aplugin:.+/))
          reject!("unknown provenance") unless known
          reject!("dynamic is not untyped") if value.fetch("state") == "dynamic" && value.fetch("type") != "untyped"
          from = value.fetch("from_site")
          reject!("invalid inferred site") if from && (!member_sites.include?(from) || provenance != "inferred")
        else
          reject!("unknown slot state")
        end
      end

      def matches?(row, site)
        return false if row["refinement"] || row["alias_target"]
        return false unless %w[start_offset end_offset].all? { |key| row.fetch("span")[key] == site.fetch("span")[key] }

        kind = row.fetch("kind")
        return site.values_at("kind", "name") == [kind, row.fetch("display_name")] if %w[class module].include?(kind)
        return false unless kind.include?("method") || kind.include?("attribute")

        scope = kind.start_with?("singleton_") ? "singleton" : "instance"
        owner = row.fetch("namespace") || "Object"
        owner = "Object" if owner.empty?
        expected_kind = kind.include?("attribute") ? "attribute" : "method"
        site.values_at("kind", "owner", "scope", "name") == [expected_kind, owner, scope, row.fetch("name")]
      end
    end
    private_constant :Document
  end
end
