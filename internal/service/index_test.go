package service

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestJobIndexSurvivesRestartAndHistoryCleanup(t *testing.T) {
	e := newEngine(t, nil)
	completed := importTest(t, e, "original")
	duplicate := importTest(t, e, "original")
	pending := importTest(t, e, "saver")
	failed := importTest(t, e, "quota")
	completed.State, failed.State = "completed", "failed"
	if err := e.save(); err != nil {
		t.Fatal(err)
	}
	if len(e.jobsByID) != len(e.state.Jobs) || e.find(duplicate.ID) != duplicate {
		t.Fatal("new and duplicate imports are missing from the index")
	}

	reopened, err := Open(e.root, nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, job := range reopened.state.Jobs {
		if reopened.find(job.ID) != job {
			t.Fatal("restart did not index the recovered job object")
		}
	}
	backing := reopened.state.Jobs
	if _, err := reopened.handle(Request{Op: "clear_completed"}, "settings"); err != nil {
		t.Fatal(err)
	}
	if len(reopened.jobsByID) != 2 || len(reopened.state.Jobs) != 2 ||
		reopened.find(completed.ID) != nil || reopened.find(duplicate.ID) != nil ||
		reopened.state.Jobs[0].ID != pending.ID || reopened.state.Jobs[1].ID != failed.ID {
		t.Fatal("history cleanup lost live jobs, kept removed IDs, or reordered the queue")
	}
	for _, job := range backing[2:] {
		if job != nil {
			t.Fatal("removed job retained by the queue backing array")
		}
	}
	for _, id := range []string{completed.ID, duplicate.ID} {
		if _, err := reopened.handle(Request{Op: "job", ID: id}, "photos"); err == nil {
			t.Fatal("removed job remains accessible through the protocol")
		}
	}
	fresh := importTest(t, reopened, "original")
	if fresh.State != "pending" || reopened.find(fresh.ID) != fresh {
		t.Fatal("new import after cleanup used a stale index")
	}
	final, err := Open(e.root, nil)
	if err != nil || len(final.state.Jobs) != 3 || final.find(fresh.ID) == nil {
		t.Fatalf("index or queue failed to survive a second restart: %v", err)
	}
}

func TestNoOpQueueCommandsDoNotRewriteState(t *testing.T) {
	for _, op := range []string{"configure", "clear_completed", "retry_failed", "clear_failed"} {
		t.Run(op, func(t *testing.T) {
			e := newEngine(t, nil)
			importTest(t, e, "original")
			path := filepath.Join(e.root, "state.json")
			before, err := os.Stat(path)
			if err != nil {
				t.Fatal(err)
			}
			options := e.state.Options
			cancelled := false
			e.active["fixture"] = func() { cancelled = true }
			if _, err := e.handle(Request{Op: op, Options: &options}, "settings"); err != nil {
				t.Fatal(err)
			}
			after, err := os.Stat(path)
			if err != nil || !os.SameFile(before, after) {
				t.Fatalf("unchanged command rewrote the atomic state file: %v", err)
			}
			if op == "configure" && !cancelled {
				t.Fatal("unchanged options skipped cancellation required by network conditions")
			}
		})
	}
}
func TestClearFailedRemovesFailedJobsAndMedia(t *testing.T) {
	e := newEngine(t, nil)
	importNamed := func(name, data string) *Job {
		t.Helper()
		r := Request{Account: "a@example.com", Quality: "original", Resources: []Resource{{Name: name, Size: int64(len(data))}}}
		v, err := e.begin(r, "photos")
		if err != nil {
			t.Fatal(err)
		}
		j := e.find(v.(map[string]any)["id"].(string))
		if err = e.appendChunk(j, Request{Index: 0, Offset: 0, Data: []byte(data)}); err != nil {
			t.Fatal(err)
		}
		if _, err = e.seal(j); err != nil {
			t.Fatal(err)
		}
		return j
	}
	pending := importNamed("pending.jpg", "1")
	failed := importNamed("failed.jpg", "2")
	completed := importNamed("completed.jpg", "3")
	failed.State = "failed"
	completed.State = "completed"
	if err := e.save(); err != nil {
		t.Fatal(err)
	}

	if _, err := os.Stat(e.jobDir(failed.ID)); err != nil {
		t.Fatalf("failed job staging directory missing before cleanup: %v", err)
	}

	backing := e.state.Jobs
	if _, err := e.handle(Request{Op: "clear_failed"}, "settings"); err != nil {
		t.Fatal(err)
	}
	if len(e.jobsByID) != 2 || len(e.state.Jobs) != 2 ||
		e.find(failed.ID) != nil || e.state.Jobs[0].ID != pending.ID || e.state.Jobs[1].ID != completed.ID {
		t.Fatal("clear_failed did not remove only failed jobs")
	}

	if _, err := os.Stat(e.jobDir(failed.ID)); !os.IsNotExist(err) {
		t.Fatalf("failed job staging directory was not deleted: %v", err)
	}

	if backing[2] != nil {
		t.Fatal("removed failed job retained by the queue backing array")
	}

	if _, err := e.handle(Request{Op: "job", ID: failed.ID}, "photos"); err == nil {
		t.Fatal("removed failed job remains accessible through the protocol")
	}

	reopened, err := Open(e.root, nil)
	if err != nil || len(reopened.state.Jobs) != 2 || reopened.find(failed.ID) != nil {
		t.Fatalf("failed cleanup did not persist after restart: %v", err)
	}
}

func TestClearAllRemovesAllJobsAndMedia(t *testing.T) {
	e := newEngine(t, nil)
	importNamed := func(name, data string) *Job {
		t.Helper()
		r := Request{Account: "a@example.com", Quality: "original", Resources: []Resource{{Name: name, Size: int64(len(data))}}}
		v, err := e.begin(r, "photos")
		if err != nil {
			t.Fatal(err)
		}
		j := e.find(v.(map[string]any)["id"].(string))
		if err = e.appendChunk(j, Request{Index: 0, Offset: 0, Data: []byte(data)}); err != nil {
			t.Fatal(err)
		}
		if _, err = e.seal(j); err != nil {
			t.Fatal(err)
		}
		return j
	}
	pending := importNamed("pending.jpg", "1")
	failed := importNamed("failed.jpg", "2")
	completed := importNamed("completed.jpg", "3")
	failed.State = "failed"
	completed.State = "completed"
	cancelled := false
	e.active[pending.ID] = func() { cancelled = true }
	if err := e.save(); err != nil {
		t.Fatal(err)
	}

	if _, err := os.Stat(e.jobDir(failed.ID)); err != nil {
		t.Fatalf("job staging directory missing before cleanup: %v", err)
	}

	backing := e.state.Jobs
	if _, err := e.handle(Request{Op: "clear_all"}, "settings"); err != nil {
		t.Fatal(err)
	}
	if !cancelled {
		t.Fatal("clear_all did not cancel active job runner")
	}
	if len(e.jobsByID) != 0 || len(e.state.Jobs) != 0 {
		t.Fatal("clear_all did not remove all jobs from queue and index")
	}
	for _, j := range []*Job{pending, failed, completed} {
		if _, err := os.Stat(e.jobDir(j.ID)); !os.IsNotExist(err) {
			t.Fatalf("job staging directory was not deleted for %s: %v", j.ID, err)
		}
		if _, err := e.handle(Request{Op: "job", ID: j.ID}, "photos"); err == nil {
			t.Fatal("removed job remains accessible through the protocol")
		}
	}
	for _, j := range backing {
		if j != nil {
			t.Fatal("removed job retained by the queue backing array")
		}
	}
	reopened, err := Open(e.root, nil)
	if err != nil || len(reopened.state.Jobs) != 0 || len(reopened.jobsByID) != 0 {
		t.Fatalf("empty queue did not persist after restart: %v", err)
	}
	path := filepath.Join(e.root, "state.json")
	before, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := e.handle(Request{Op: "clear_all"}, "settings"); err != nil {
		t.Fatal(err)
	}
	after, err := os.Stat(path)
	if err != nil || !os.SameFile(before, after) {
		t.Fatalf("empty clear_all rewrote the atomic state file: %v", err)
	}
}


func TestChangedOptionsAndRetryArePersisted(t *testing.T) {
	e := newEngine(t, nil)
	job := importTest(t, e, "original")
	options := e.state.Options
	options.Concurrent = 2
	if _, err := e.handle(Request{Op: "configure", Options: &options}, "settings"); err != nil {
		t.Fatal(err)
	}
	for _, op := range []string{"retry", "retry_failed"} {
		job.State, job.Attempts, job.Next, job.CancelRequested = "failed", 4, 12345, true
		if err := e.save(); err != nil {
			t.Fatal(err)
		}
		if _, err := e.handle(Request{Op: op, ID: job.ID}, "settings"); err != nil {
			t.Fatal(err)
		}
		var state State
		data, err := os.ReadFile(filepath.Join(e.root, "state.json"))
		if err != nil || json.Unmarshal(data, &state) != nil {
			t.Fatal("cannot read persisted retry state")
		}
		saved := state.Jobs[0]
		if state.Options != options || saved.State != "pending" || saved.Attempts != 0 || saved.Next != 0 || saved.CancelRequested {
			t.Fatal("changed options or retry reset was not persisted")
		}
	}
}

var benchmarkJob *Job
var benchmarkSummary any

func benchmarkEngine(b *testing.B, count int) *Engine {
	b.Helper()
	state := State{Version: 1, Options: defaults(), Jobs: make([]*Job, count)}
	for i := range state.Jobs {
		state.Jobs[i] = &Job{ID: fmt.Sprintf("%032x", i), Account: "fixture@example.com", Quality: []string{"original", "saver", "quota"}[i%3], State: "pending", Owner: "photos", Resources: []Resource{{Name: "fixture.heic", Size: 3}}, Total: 3}
	}
	root := b.TempDir()
	if err := atomicJSON(filepath.Join(root, "state.json"), state); err != nil {
		b.Fatal(err)
	}
	e, err := Open(root, nil)
	if err != nil {
		b.Fatal(err)
	}
	return e
}

func BenchmarkJobLookup(b *testing.B) {
	for _, count := range []int{100, MaxJobs} {
		b.Run(fmt.Sprint(count), func(b *testing.B) {
			e := benchmarkEngine(b, count)
			id := e.state.Jobs[count-1].ID
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				benchmarkJob = e.find(id)
			}
		})
	}
}

func BenchmarkUploadSummary(b *testing.B) {
	e := benchmarkEngine(b, MaxJobs)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		benchmarkSummary = e.uploadSummary()
	}
}
