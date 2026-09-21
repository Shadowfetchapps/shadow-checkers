extends SceneTree

## Confirms AI search runs off the main thread so the frame loop keeps pumping.


func _initialize() -> void:
	_run()


func _run() -> void:
	print("Running Shadow Checkers worker/UI yield test...")
	var job := CheckersAI.SearchJob.new()
	job.fen = CheckersTypes.START_FEN
	job.difficulty = "master"
	var t0 := Time.get_ticks_msec()
	var task_id := WorkerThreadPool.add_task(Callable(job, "run"), true, "shadow-checkers-verify")
	var pumps := 0
	while not WorkerThreadPool.is_task_completed(task_id):
		await create_timer(0.0).timeout
		pumps += 1
		if Time.get_ticks_msec() - t0 > 4000:
			break
	WorkerThreadPool.wait_for_task_completion(task_id)
	var dt := Time.get_ticks_msec() - t0
	var ok := job.move_uci.length() >= 4 and pumps >= 3
	print("  job uci   ", job.move_uci)
	print("  pumps     ", pumps)
	print("  elapsed   ", dt, "ms")
	print("  nodes     ", job.nodes)
	if ok:
		print("PASS  AI worker yielded to the main loop")
		quit(0)
	else:
		print("FAIL  AI worker did not yield or returned no move")
		quit(1)
