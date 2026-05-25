def tail_log(log_filename, nr_of_lines = 10)
  tries ||= 3
  `tail -n #{nr_of_lines} "#{log_filename}"`
rescue => e
  unless (tries -= 1) == 0
    sleep(1)
    retry
  end
end
