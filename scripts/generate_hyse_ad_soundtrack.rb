#!/usr/bin/env ruby
# Generates an original, high-energy 30-second electronic advertising cue
# for Hyse. No samples or third-party recordings are used.

require "fileutils"

SAMPLE_RATE = 44_100
DURATION = 30.0
TAU = 2.0 * Math::PI
OUTPUT = File.expand_path("../SocialMediaAssets/audio", __dir__)
FileUtils.mkdir_p(OUTPUT)

left = Array.new((SAMPLE_RATE * DURATION).to_i, 0.0)
right = Array.new(left.length, 0.0)
random = Random.new(20_260_827)

def mix(left, right, index, value, pan)
  return if index.negative? || index >= left.length
  angle = (pan + 1.0) * Math::PI / 4.0
  left[index] += value * Math.cos(angle)
  right[index] += value * Math.sin(angle)
end

def add_tone(left, right, start, length, frequency, level, pan: 0.0, attack: 0.012, release: 4.8, color: 0.16)
  first = (start * SAMPLE_RATE).to_i
  count = (length * SAMPLE_RATE).to_i
  count.times do |offset|
    t = offset.to_f / SAMPLE_RATE
    envelope = [1.0, t / attack].min * Math.exp(-release * t / length)
    wave = Math.sin(TAU * frequency * t) + color * Math.sin(TAU * frequency * 2.01 * t)
    mix(left, right, first + offset, level * envelope * wave, pan)
  end
end

def add_synth(left, right, start, length, frequency, level, pan: 0.0, release: 8.5)
  first = (start * SAMPLE_RATE).to_i
  count = (length * SAMPLE_RATE).to_i
  count.times do |offset|
    t = offset.to_f / SAMPLE_RATE
    envelope = [1.0, t / 0.004].min * Math.exp(-release * t / length)
    wave = Math.sin(TAU * frequency * t) +
           0.48 * Math.sin(TAU * frequency * 2.0 * t) +
           0.25 * Math.sin(TAU * frequency * 3.0 * t) +
           0.12 * Math.sin(TAU * frequency * 4.03 * t)
    mix(left, right, first + offset, level * envelope * wave, pan)
  end
end

def add_bass(left, right, start, length, frequency, level)
  first = (start * SAMPLE_RATE).to_i
  count = (length * SAMPLE_RATE).to_i
  count.times do |offset|
    t = offset.to_f / SAMPLE_RATE
    envelope = [1.0, t / 0.006].min * Math.exp(-5.6 * t / length)
    drive = Math.sin(TAU * frequency * t) + 0.42 * Math.sin(TAU * frequency * 2.0 * t)
    mix(left, right, first + offset, Math.tanh(drive * 1.7) * level * envelope, 0.0)
  end
end

def add_pad(left, right, start, length, frequencies, level)
  frequencies.each_with_index do |frequency, index|
    first = (start * SAMPLE_RATE).to_i
    count = (length * SAMPLE_RATE).to_i
    pan = [-0.55, 0.0, 0.55][index % 3]
    count.times do |offset|
      t = offset.to_f / SAMPLE_RATE
      attack = [1.0, t / 0.7].min
      tail = [1.0, (length - t) / 0.8].min
      pulse = 0.84 + 0.16 * Math.sin(TAU * 0.18 * t + index)
      wave = Math.sin(TAU * frequency * t) + 0.12 * Math.sin(TAU * frequency * 2.0 * t)
      mix(left, right, first + offset, level * attack * tail * pulse * wave, pan)
    end
  end
end

def add_kick(left, right, start, level)
  first = (start * SAMPLE_RATE).to_i
  count = (0.34 * SAMPLE_RATE).to_i
  phase = 0.0
  count.times do |offset|
    t = offset.to_f / SAMPLE_RATE
    frequency = 46.0 + 78.0 * Math.exp(-22.0 * t)
    phase += TAU * frequency / SAMPLE_RATE
    envelope = Math.exp(-13.0 * t)
    mix(left, right, first + offset, level * envelope * Math.sin(phase), 0.0)
  end
end

def add_hat(left, right, start, level, random, pan)
  first = (start * SAMPLE_RATE).to_i
  count = (0.075 * SAMPLE_RATE).to_i
  previous = 0.0
  count.times do |offset|
    t = offset.to_f / SAMPLE_RATE
    noise = random.rand(-1.0..1.0)
    high = noise - previous * 0.82
    previous = noise
    mix(left, right, first + offset, level * Math.exp(-48.0 * t) * high, pan)
  end
end

def add_snare(left, right, start, level, random)
  first = (start * SAMPLE_RATE).to_i
  count = (0.18 * SAMPLE_RATE).to_i
  count.times do |offset|
    t = offset.to_f / SAMPLE_RATE
    noise = random.rand(-1.0..1.0)
    body = Math.sin(TAU * 185.0 * t) * Math.exp(-25.0 * t)
    value = level * Math.exp(-19.0 * t) * (noise * 0.72 + body * 0.45)
    mix(left, right, first + offset, value, offset.even? ? -0.08 : 0.08)
  end
end

def add_riser(left, right, start, length, level, random)
  first = (start * SAMPLE_RATE).to_i
  count = (length * SAMPLE_RATE).to_i
  phase = 0.0
  count.times do |offset|
    t = offset.to_f / SAMPLE_RATE
    progress = t / length
    frequency = 180.0 + 1_100.0 * progress * progress
    phase += TAU * frequency / SAMPLE_RATE
    noise = random.rand(-1.0..1.0) * 0.22
    envelope = progress * progress * [1.0, (length - t) / 0.08].min
    mix(left, right, first + offset, level * envelope * (Math.sin(phase) + noise), progress * 1.4 - 0.7)
  end
end

beat = 60.0 / 122.0
bar = beat * 4.0

# Premium minimalist technology cue in F-sharp minor: energetic through
# rhythm and movement, not through oversized drops or novelty synths.
chords = [
  [92.50, 110.00, 138.59],  # F#m
  [73.42, 110.00, 146.83],  # D
  [110.00, 138.59, 164.81], # A
  [82.41, 123.47, 164.81]   # E
]
roots = [46.25, 36.71, 55.00, 41.20]

# Precise opening identity with space for the first visual reveal.
add_kick(left, right, 0.08, 0.18)
[[0.32, 369.99], [0.86, 440.00], [1.43, 554.37], [2.12, 493.88]].each_with_index do |(start, frequency), index|
  add_tone(left, right, start, 0.52, frequency, 0.12, pan: [-0.28, 0.18, -0.10, 0.26][index],
           attack: 0.008, release: 7.0, color: 0.21)
end

# A very quiet harmonic bed adds polish without making the track sleepy.
16.times do |bar_index|
  start = bar_index * bar
  break if start >= 28.0
  chord = chords[bar_index % 4]
  add_pad(left, right, start, [bar + 0.08, DURATION - start].min, chord, start < 5.0 ? 0.010 : 0.014)
  [0.0, beat * 1.5, beat * 3.0].each do |offset|
    chord.each_with_index do |frequency, note|
      add_tone(left, right, start + offset, beat * 0.46, frequency * 2.0,
               start < 7.0 ? 0.020 : 0.029, pan: [-0.50, 0.0, 0.50][note],
               attack: 0.006, release: 8.8, color: 0.18)
    end
  end
end

# Controlled pulse: deep but restrained kick, muted bass and fine percussion.
(6...58).each do |beat_index|
  start = beat_index * beat
  break if start >= 28.3
  reduced = (24.0...25.1).cover?(start)
  full_energy = start >= 9.5 && !reduced
  add_kick(left, right, start, full_energy ? 0.205 : 0.145) if !reduced && (full_energy || beat_index.even?)
  add_snare(left, right, start, full_energy ? 0.040 : 0.024, random) if beat_index % 4 == 1 || beat_index % 4 == 3
  root = roots[(beat_index / 4) % roots.length]
  bass_note = beat_index % 4 == 3 && full_energy ? root * 1.5 : root
  add_bass(left, right, start, beat * 0.66, bass_note, full_energy ? 0.068 : 0.048) unless reduced
  add_hat(left, right, start + beat / 2.0, full_energy ? 0.030 : 0.017, random, beat_index.even? ? -0.42 : 0.42)
  if full_energy
    add_hat(left, right, start + beat * 0.75, 0.014, random, beat_index.even? ? 0.24 : -0.24)
  end
end

# Elegant build: short pulses gradually tighten before the main section.
(0...12).each do |step|
  start = 5.35 + step * beat / 2.0
  frequency = [369.99, 440.00, 493.88, 554.37][step % 4]
  add_tone(left, right, start, beat * 0.28, frequency, 0.050 + step * 0.002,
           pan: step.even? ? -0.28 : 0.28, attack: 0.004, release: 9.5, color: 0.22)
end
add_riser(left, right, 8.60, 0.88, 0.044, random)

# Main theme: a clean, understated melodic line with forward motion.
theme_a = [554.37, 659.25, nil, 440.00, 493.88, 554.37, 369.99, nil,
           440.00, 493.88, 659.25, nil, 554.37, 493.88, 440.00, nil]
theme_b = [493.88, 554.37, 739.99, nil, 659.25, 554.37, 493.88, 440.00,
           nil, 659.25, 739.99, 659.25, 554.37, nil, 493.88, 369.99]
[[9.55, theme_a], [13.50, theme_b], [17.45, theme_a], [21.40, theme_b]].each_with_index do |(phrase_start, notes), phrase|
  notes.each_with_index do |frequency, step|
    next unless frequency
    accent = [0, 5, 10].include?(step) ? 1.18 : 1.0
    add_tone(left, right, phrase_start + step * beat / 2.0, beat * 0.38, frequency,
             0.079 * accent, pan: step.even? ? -0.20 : 0.20,
             attack: 0.005, release: phrase.odd? ? 8.5 : 7.5, color: 0.24)
  end
end

# Brief reduction and refined lift into the closing product shot.
add_riser(left, right, 24.10, 0.92, 0.052, random)
(0...8).each do |step|
  add_tone(left, right, 24.20 + step * beat / 4.0, beat * 0.20,
           369.99 * (1.0 + step * 0.025), 0.038 + step * 0.003,
           pan: step.even? ? -0.30 : 0.30, attack: 0.004, release: 10.0, color: 0.20)
end

# Closing section has more momentum without turning into a festival drop.
[25.10, 25.59, 26.08, 26.57, 27.06, 27.55, 28.04].each_with_index do |start, index|
  add_kick(left, right, start, 0.225)
  add_bass(left, right, start, beat * 0.65, index.odd? ? 69.30 : 46.25, 0.073)
end
[[25.10, 554.37], [25.59, 659.25], [26.08, 739.99], [26.57, 659.25],
 [27.06, 554.37], [27.55, 493.88], [28.04, 369.99]].each_with_index do |(start, frequency), index|
  add_tone(left, right, start, beat * 0.40, frequency, 0.090,
           pan: index.even? ? -0.22 : 0.22, attack: 0.005, release: 8.0, color: 0.25)
end
add_kick(left, right, 28.72, 0.245)
[184.99, 220.00, 277.18].each_with_index do |frequency, index|
  add_tone(left, right, 28.72, 0.98, frequency, 0.070,
           pan: [-0.38, 0.0, 0.38][index], attack: 0.012, release: 4.0, color: 0.16)
end

# Gentle master saturation plus short fades for clean video edits.
pcm = left.each_index.flat_map do |index|
  time = index.to_f / SAMPLE_RATE
  fade_in = [1.0, time / 0.16].min
  fade_out = [1.0, (DURATION - time) / 0.55].min
  gain = fade_in * fade_out
  [left[index], right[index]].map do |sample|
    shaped = Math.tanh(sample * 1.75) * 0.94 * gain
    ([[shaped, -0.98].max, 0.98].min * 32_767).to_i
  end
end.pack("s<*")

byte_rate = SAMPLE_RATE * 4
header = "RIFF" + [36 + pcm.bytesize].pack("V") + "WAVEfmt " +
         [16, 1, 2, SAMPLE_RATE, byte_rate, 4, 16].pack("VvvVVvv") +
         "data" + [pcm.bytesize].pack("V")

wav = File.join(OUTPUT, "hyse-ad-soundtrack-30s.wav")
File.binwrite(wav, header + pcm)
puts wav
