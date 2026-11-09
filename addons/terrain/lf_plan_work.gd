class_name LFPlanWork
extends RefCounted
## The planning searches' sampling (LFSitePlanner's spot searches, LFTerrainRoads.route's grid) spread over
## the worker threads. Each band of the work gets its own LFTerrainGenerator.clone_for_worker() (a generator
## keeps scratch state while it samples), and a body only reads the generator, so the bands are independent
## and the answer is the one the same search gives on one thread, bit for bit (test_plan_work proves it).
## Nothing here changes a world: only how long planning it takes.


## Threads the planning searches run on: 0 = every core but one (at least one), 1 = the calling thread only
## (the same results, slower). Set it before a world is planned.
static var threads := 0


## The thread count `threads` means.
static func count() -> int:
	return threads if threads > 0 else maxi(1, OS.get_processor_count() - 1)


## Runs `body(generator copy, i0, i1)` over the items 0..n-1, split into one band per thread (at most n), on
## the worker threads (high priority; waits for them all), and returns each band's result in band order
## (the bands cover the items in order, so the results read as the items do). A body samples its copy and
## builds its result from the items alone: it must not touch anything shared. `gen` null: the body gets null
## (work that samples nothing).
static func run(gen: LFTerrainGenerator, n: int, body: Callable) -> Array:
	var bands := mini(count(), n)
	if bands <= 0:
		return []
	var per := (n + bands - 1) / bands
	bands = (n + per - 1) / per   # no empty bands at the end
	var out := []
	out.resize(bands)
	var mutex := Mutex.new()
	var work := func(k: int) -> void:
		var r: Variant = body.call(gen.clone_for_worker() if gen != null else null, k * per, mini((k + 1) * per, n))
		mutex.lock()
		out[k] = r
		mutex.unlock()
	if bands == 1:
		work.call(0)
		return out
	var id := WorkerThreadPool.add_group_task(work, bands, -1, true, "LF plan work")
	WorkerThreadPool.wait_for_group_task_completion(id)
	return out


## A sequential search `for i in n: candidate = draw(rng); result = eval(candidate); no good: continue;
## keep the best; if i > stop: break` (so it stops at the first candidate past `stop` that is any good), run in
## parallel batches with the same answer: the best result (the lowest result[0], the first on a tie) among the
## candidates the sequential search would have looked at, and `rng` left as it would have left it (just after
## the last candidate it drew). `draw(rng)` makes one candidate from the rng (and must use the rng exactly as
## the sequential search did); `eval(generator copy, candidate, its index)` gives [] when it is no good, else
## [score, ...] (a score of INF: no good either, but worth keeping in `results`); pure: it reads the generator
## and the candidate only. Returns the best's [...] after its score, or [] when none was found. `results`, if
## given, gets every evaluated candidate's eval result in candidate order (a later search over the same
## candidates can reuse what doesn't change).
static func search(gen: LFTerrainGenerator, rng: RandomNumberGenerator, n: int, stop: int, draw: Callable, eval: Callable,
		results: Array = []) -> Array:
	var cands := []
	var states := PackedInt64Array()   # rng.state after each draw
	var best := []
	var best_score := INF
	var i0 := 0
	while i0 < n:
		# the first batch reaches the first index the search may stop at, the rest are a few per thread
		var i1 := mini(i0 + (stop + 2 if i0 == 0 else 16 * count()), n)
		while cands.size() < i1:
			cands.append(draw.call(rng))
			states.append(rng.state)
		var batch := i0
		var res := run(gen, i1 - i0, func(g: LFTerrainGenerator, a: int, b: int) -> Array:
			var out := []
			for i in range(a, b):
				out.append(eval.call(g, cands[batch + i], batch + i))
			return out)
		var k := i0
		for band: Array in res:
			for r: Array in band:
				results.append(r)
				if not r.is_empty() and float(r[0]) < INF:
					if float(r[0]) < best_score:
						best_score = float(r[0])
						best = r.slice(1)
					if k > stop:
						rng.state = states[k]
						return best
				k += 1
		i0 = i1
	if n > 0:
		rng.state = states[n - 1]
	return best
