require Vagrant.source_root.join("plugins/synced_folders/rsync/helper")
require 'listen'

module Vagrant
  module Rsyncer
    class Command < Vagrant.plugin(2, :command)

      def self.synopsis
        "does a full sync and watches the changed files to sync"
      end

      def execute
        with_target_vms do |machine|
          full_sync(machine)
          watch(machine, method(:rsync_path))
        end
        0
      end

      def rsync_path(machine, path_opts)
        VagrantPlugins::SyncedFolderRSync::RsyncHelper.rsync_single(
          machine,
          machine.ssh_info,
          path_opts
        )
      end

      private

      def parse_path_opts(path)
        path_opts = {}
        path_opts[:guestpath] = path['target']['path']
        path_opts[:owner] = path['target']['user']
        path_opts[:group] = path['target']['group']
        path_opts[:exclude] = path['source']['excludes']
        path_opts[:args] = []

        if path['target']['permissions']
          if path['target']['permissions']['user']
            path_opts[:args] << '--chmod=u=' + path['target']['permissions']['user']
          end

          if path['target']['permissions']['group']
            path_opts[:args] << '--chmod=g=' + path['target']['permissions']['group']
          end

          if path['target']['permissions']['other']
            path_opts[:args] << '--chmod=o=' + path['target']['permissions']['other']
          end
        end

        path_opts
      end

      def full_sync(machine)
        machine.ui.info(I18n.t('rsyncer.info.started'))

        verbose = machine.config.rsyncer.settings['verbose']
        rsync_args = machine.config.rsyncer.settings['args']['rsync']

        machine.config.rsyncer.settings['paths'].each do |path|
          path_opts = {}
          path_opts[:args] = rsync_args
          path_opts[:hostpath] = File.expand_path(path['source']['path'], machine.env.root_path)
          path_opts[:verbose] = verbose
          path_opts = path_opts.merge(parse_path_opts(path))
          rsync_path(machine, path_opts)
        end
      end

      def watch(machine, callback)
        machine.ui.info(I18n.t('rsyncer.info.watching'))

        verbose = machine.config.rsyncer.settings['verbose']
        rsync_args = machine.config.rsyncer.settings['args']['rsync']

        machine.config.rsyncer.settings['paths'].each do |path|
          next unless path['source']['watch']

          hostpath = File.expand_path(path['source']['path'], machine.env.root_path)
          path_opts = {}
          path_opts[:args] = rsync_args
          path_opts[:verbose] = verbose
          path_opts = path_opts.merge(parse_path_opts(path))
          watch_opts = {
            latency: path['source']['latency']
          }

          listener = Listen.to(hostpath, watch_opts) do |modified, added, removed|
            (modified + added + removed).map do |change|
              path_opts[:hostpath] = File.expand_path(change, machine.env.root_path)
              # TODO: format the hostpath for Vagrant RsyncHelper
              #callback.call(machine, path_opts)
            end
          end
          listener.start
        end

        sleep
      end

    end
  end
end