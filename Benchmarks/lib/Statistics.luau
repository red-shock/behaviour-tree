local Statistics = {}

function Statistics.percentile(values, fraction)
	assert(#values > 0, "Cannot summarise an empty sample")
	assert(fraction >= 0 and fraction <= 1, "Invalid percentile")
	local sorted = table.clone(values)
	table.sort(sorted)
	local position = 1 + (#sorted - 1) * fraction
	local lower = math.floor(position)
	local upper = math.ceil(position)
	return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower)
end

function Statistics.summarise(values)
	return {
		median = Statistics.percentile(values, 0.5),
		p10 = Statistics.percentile(values, 0.1),
		p90 = Statistics.percentile(values, 0.9),
		minimum = Statistics.percentile(values, 0),
		maximum = Statistics.percentile(values, 1),
	}
end

function Statistics.compare(baseline, candidate, iterations)
	assert(#baseline == #candidate and #baseline > 0, "Expected paired samples")
	assert(iterations > 0, "Expected positive iteration count")
	local baselineUs, candidateUs, reductions = {}, {}, {}
	for index, before in ipairs(baseline) do
		local after = candidate[index]
		assert(before > 0 and after > 0, "Timer resolution is insufficient")
		baselineUs[index] = before * 1e6 / iterations
		candidateUs[index] = after * 1e6 / iterations
		reductions[index] = 100 * (before - after) / before
	end
	return {
		baselineMicroseconds = Statistics.summarise(baselineUs),
		candidateMicroseconds = Statistics.summarise(candidateUs),
		pairedReductionPercent = Statistics.summarise(reductions),
	}
end

return Statistics
