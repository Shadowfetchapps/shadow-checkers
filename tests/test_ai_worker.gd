extends SceneTree

## Confirms AI search runs off the main thread so the frame loop keeps pumping,
## and that cancelling a running job stops it quickly.

var _fails := 0


func _initialize() -> void:
	_run()


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("PASS  ", name)
	else:
		_fails += 1
		print("FAIL  ", name, "" if detail.is_empty() else " — " + detail)


func _legal(job: CheckersAI.SearchJob) -> bool:
	var e := CheckersEngine.new(job.variant)
	if not job.start_fen.is_empty():
		e.from_fen(job.start_fen)
	for u in job.moves_uci:
		e.apply_move(e.find_uci(u))
	return e.find_uci(job.best_uci) != null


func _pump(job: CheckersAI.SearchJob, limit_ms: int, cancel_after_ms: int = -1) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var task_id := WorkerThreadPool.add_task(Callable(job, "run"), true, "shadow-checkers-verify")
	var pumps := 0
	var cancel_at := -1
	while not WorkerThreadPool.is_task_completed(task_id):
		await create_timer(0.0).timeout
		pumps += 1
		var now := Time.get_ticks_msec() - t0
		if cancel_after_ms >= 0 and cancel_at < 0 and now >= cancel_after_ms:
			job.cancelled = true
			cancel_at = now
		if now > limit_ms:
			break
	WorkerThreadPool.wait_for_task_completion(task_id)
	var dt := Time.get_ticks_msec() - t0
	return {"pumps": pumps, "elapsed": dt, "cancel_at": cancel_at}


func _run() -> void:
	print("Running Shadow Checkers worker/UI yield test...")
	CheckersAI.warmup()
	# 1. Master search out of book on a worker while the main loop pumps.
	var job := CheckersAI.SearchJob.new()
	job.variant = "english"
	job.moves_uci = PackedStringArray(["f6e5", "c3d4", "e5c3", "b2d4"])
	job.level = "master"
	job.use_book = false
	var r: Dictionary = await _pump(job, 6000)
	print("  job uci   ", job.best_uci, "  depth ", job.depth, "  nodes ", job.nodes, "  nps ", job.nps)
	print("  pumps     ", r["pumps"], "  elapsed ", r["elapsed"], "ms")
	_check("AI worker yielded to the main loop", int(r["pumps"]) >= 3)
	_check("worker job returned a legal move", job.done and _legal(job), job.best_uci)
	_check("master used its time budget sensibly", int(r["elapsed"]) < 4000, str(r["elapsed"]))
	# 2. Cancellation: a long analysis stops within a few hundred ms.
	for v in ["english", "russian", "brazilian"]:
		var long := CheckersAI.SearchJob.new()
		long.variant = v
		long.level = "analysis"
		long.time_ms = 20000
		var c: Dictionary = await _pump(long, 8000, 400)
		var after := int(c["elapsed"]) - int(c["cancel_at"])
		print("  %s cancel: stopped %d ms after cancel (depth %d, %d nodes)" % [v, after, long.depth, long.nodes])
		_check("%s cancellation stops quickly" % v, int(c["cancel_at"]) >= 0 and after < 350, str(after))
		_check("%s cancelled job still has a legal move" % v, long.done and _legal(long), long.best_uci)
	print("worker tests: %s" % ("ok" if _fails == 0 else "%d failed" % _fails))
	quit(0 if _fails == 0 else 1)
