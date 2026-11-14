#!/usr/bin/env ruby
# Generates a short original confirmation chime for completed training sets.

require "tmpdir"

sample_rate = 44_100
duration = 0.42
samples = Array.new((sample_rate * duration).to_i, 0.0)

# A quiet rising major third with a rounded, mallet-like timbre. The two notes
# overlap gently instead of making the sharp, high-pitched double beep.
[[0.0, 0.36, 349.23, 0.24], [0.065, 0.31, 440.0, 0.17]].each do |start, length, frequency, level|
  first = (start * sample_rate).to_i
  count = (length * sample_rate).to_i
  count.times do |offset|
    time = offset.to_f / sample_rate
    attack = Math.sin(Math::PI / 2 * [time / 0.018, 1.0].min)**2
    tail = Math.sin(Math::PI / 2 * [(length - time) / 0.07, 1.0].min)**2
    release = Math.exp(-3.1 * time / length)
    fundamental = Math.sin(2 * Math::PI * frequency * time)
    soft_harmonics = Math.exp(-7.0 * time / length) * (
      0.09 * Math.sin(4 * Math::PI * frequency * time) +
      0.025 * Math.sin(6 * Math::PI * frequency * time)
    )
    samples[first + offset] += level * attack * tail * release * (fundamental + soft_harmonics)
  end
end

pcm = samples.map { |value| ([[value, -0.98].max, 0.98].min * 32_767).to_i }.pack("s<*")
header = "RIFF" + [36 + pcm.bytesize].pack("V") + "WAVEfmt " +
  [16, 1, 1, sample_rate, sample_rate * 2, 2, 16].pack("VvvVVvv") +
  "data" + [pcm.bytesize].pack("V")
wav = File.join(Dir.tmpdir, "hyse-set-complete-#{Process.pid}.wav")
caf = File.expand_path("../CalorieTrackerApp/Sounds/hyse-set-complete.caf", __dir__)

begin
  File.binwrite(wav, header + pcm)
  abort "afconvert failed" unless system("/usr/bin/afconvert", "-f", "caff", "-d", "LEI16@44100", wav, caf)
ensure
  File.delete(wav) if File.exist?(wav)
end
