#!/usr/bin/env ruby
# Generates Hyse's original rest-complete chimes from simple synthesized tones.
# No third-party samples or copyrighted recordings are used.

require "fileutils"
require "tmpdir"

SAMPLE_RATE = 44_100
DURATION = 1.35
OUTPUT = File.expand_path("../CalorieTrackerApp/Sounds", __dir__)
FileUtils.mkdir_p(OUTPUT)

variants = {
  "alert" => [[0.00, 0.16, 880.00, 0.58], [0.19, 0.16, 880.00, 0.54], [0.43, 0.28, 1174.66, 0.48], [0.43, 0.22, 220.00, 0.22]],
  "signature" => [[0.00, 0.38, 523.25, 0.42], [0.22, 0.52, 659.25, 0.34], [0.48, 0.68, 783.99, 0.28]],
  "soft" => [[0.00, 0.58, 392.00, 0.34], [0.30, 0.72, 523.25, 0.27]],
  "bright" => [[0.00, 0.30, 659.25, 0.38], [0.18, 0.38, 783.99, 0.34], [0.40, 0.58, 987.77, 0.25]]
}

variants.each do |name, notes|
  samples = Array.new((SAMPLE_RATE * DURATION).to_i, 0.0)
  notes.each do |start, length, frequency, level|
    first = (start * SAMPLE_RATE).to_i
    count = (length * SAMPLE_RATE).to_i
    count.times do |offset|
      t = offset.to_f / SAMPLE_RATE
      attack = [1.0, t / 0.018].min
      release = Math.exp(-4.8 * t / length)
      fundamental = Math.sin(2 * Math::PI * frequency * t)
      overtone = 0.16 * Math.sin(2 * Math::PI * frequency * 2.01 * t)
      samples[first + offset] += level * attack * release * (fundamental + overtone)
    end
  end
  pcm = samples.map { |value| [[value, -0.98].max, 0.98].min * 32_767 }.map(&:to_i).pack("s<*")
  byte_rate = SAMPLE_RATE * 2
  header = "RIFF" + [36 + pcm.bytesize].pack("V") + "WAVEfmt " + [16, 1, 1, SAMPLE_RATE, byte_rate, 2, 16].pack("VvvVVvv") + "data" + [pcm.bytesize].pack("V")
  wav = File.join(Dir.tmpdir, "hyse-rest-#{name}-#{Process.pid}.wav")
  caf = File.join(OUTPUT, "hyse-rest-#{name}.caf")
  File.binwrite(wav, header + pcm)
  abort "afconvert failed for #{name}" unless system("/usr/bin/afconvert", "-f", "caff", "-d", "LEI16@44100", wav, caf)
  File.delete(wav) if File.exist?(wav)
end
