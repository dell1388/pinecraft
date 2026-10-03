extends RefCounted

## The big jobs of building the world, on the worker threads.
##
## A job is split over every core but a few, so the rest of the computer keeps
## some to itself while the world is built rather than grinding along at full
## load. And while it works, the one that asked can let frames go by (pass the
## SceneTree), so the loading screen goes on drawing and the window never
## locks up and goes "Not Responding" for the length of it. Without a tree the
## job is simply waited for, as any other call would be.
##
## No class_name: each script that uses it preloads it as `Workers`, so it
## works before the editor has rescanned the project for new class names.

## How many threads a big job is split over: all but a quarter of the cores
## (at least one kept back), so a 16-thread machine uses 12, an 8-thread one
## 6, a 4-thread one 3.
static func tasks() -> int:
	var n := OS.get_processor_count()
	if n <= 2:
		return n
	return n - maxi(1, n / 4)

## `job(i)` for every i from 0 to count - 1, across the worker threads.
static func group(job: Callable, count: int, what: String, tree: SceneTree = null) -> void:
	if count <= 0:
		return
	var task := WorkerThreadPool.add_group_task(job, count, mini(count, tasks()), true, what)
	if tree != null:
		while not WorkerThreadPool.is_group_task_completed(task):
			await tree.process_frame
	WorkerThreadPool.wait_for_group_task_completion(task)

## `job()` once. With a tree it runs on a worker thread while frames go by
## here; without one it runs here and now.
static func one(job: Callable, what: String, tree: SceneTree = null) -> void:
	if tree == null:
		job.call()
		return
	var id := WorkerThreadPool.add_task(job, true, what)
	while not WorkerThreadPool.is_task_completed(id):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(id)
