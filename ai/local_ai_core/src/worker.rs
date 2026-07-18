use std::collections::VecDeque;
use std::sync::mpsc::{self, SyncSender, TrySendError};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};

use crate::{
    AiError, AiErrorCode, AiRequest, AiRequestIdentity, AiResponse, LocalAiProvider, ProviderHealth,
};

pub const DEFAULT_AI_WORK_QUEUE_CAPACITY: usize = 2;
pub const DEFAULT_AI_COMPLETION_CAPACITY: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiSubmitStatus {
    Accepted,
    QueueFull,
    Unavailable,
}

#[derive(Debug)]
pub struct AiWorkerCompletion {
    identity: AiRequestIdentity,
    result: Result<AiResponse, AiError>,
}

impl AiWorkerCompletion {
    pub const fn identity(&self) -> AiRequestIdentity {
        self.identity
    }

    pub fn result(&self) -> &Result<AiResponse, AiError> {
        &self.result
    }

    pub fn into_result(self) -> Result<AiResponse, AiError> {
        self.result
    }
}

/// Runs synchronous providers away from latency-sensitive host threads.
///
/// Both pending work and completed results are bounded. Queue saturation drops new
/// optional AI work instead of blocking base IME input.
pub struct BoundedAiWorker {
    provider: Arc<dyn LocalAiProvider>,
    command_tx: Option<SyncSender<AiRequest>>,
    completed: Arc<Mutex<VecDeque<AiWorkerCompletion>>>,
    worker: Option<JoinHandle<()>>,
}

impl BoundedAiWorker {
    pub fn new(provider: Arc<dyn LocalAiProvider>) -> Result<Self, AiError> {
        Self::with_capacities(
            provider,
            DEFAULT_AI_WORK_QUEUE_CAPACITY,
            DEFAULT_AI_COMPLETION_CAPACITY,
        )
    }

    pub fn with_capacities(
        provider: Arc<dyn LocalAiProvider>,
        work_capacity: usize,
        completion_capacity: usize,
    ) -> Result<Self, AiError> {
        if work_capacity == 0 || completion_capacity == 0 {
            return Err(AiError::new(AiErrorCode::InvalidBudget));
        }

        let (command_tx, command_rx) = mpsc::sync_channel::<AiRequest>(work_capacity);
        let completed = Arc::new(Mutex::new(VecDeque::with_capacity(completion_capacity)));
        let worker_completed = Arc::clone(&completed);
        let worker_provider = Arc::clone(&provider);
        let worker = thread::Builder::new()
            .name("private-pinyin-ai-lite".to_string())
            .spawn(move || {
                while let Ok(request) = command_rx.recv() {
                    let identity = request.identity();
                    let result = if request.deadline().is_expired() {
                        Err(AiError::new(AiErrorCode::Timeout))
                    } else {
                        worker_provider.infer(&request)
                    };
                    if let Ok(mut queue) = worker_completed.lock() {
                        if queue.len() == completion_capacity {
                            queue.pop_front();
                        }
                        queue.push_back(AiWorkerCompletion { identity, result });
                    }
                }
            })
            .map_err(|_| AiError::new(AiErrorCode::Internal))?;

        Ok(Self {
            provider,
            command_tx: Some(command_tx),
            completed,
            worker: Some(worker),
        })
    }

    pub fn try_submit(&self, request: AiRequest) -> AiSubmitStatus {
        if self.provider.health() != ProviderHealth::Available || request.deadline().is_expired() {
            return AiSubmitStatus::Unavailable;
        }
        let Some(command_tx) = &self.command_tx else {
            return AiSubmitStatus::Unavailable;
        };
        match command_tx.try_send(request) {
            Ok(()) => AiSubmitStatus::Accepted,
            Err(TrySendError::Full(_)) => AiSubmitStatus::QueueFull,
            Err(TrySendError::Disconnected(_)) => AiSubmitStatus::Unavailable,
        }
    }

    pub fn take_completed(&self, identity: AiRequestIdentity) -> Option<AiWorkerCompletion> {
        let mut completed = self.completed.lock().ok()?;
        let index = completed
            .iter()
            .position(|completion| completion.identity == identity)?;
        completed.remove(index)
    }

    pub fn cancel(&self, identity: AiRequestIdentity) {
        self.provider.cancel(identity);
        if let Ok(mut completed) = self.completed.lock() {
            completed.retain(|completion| completion.identity != identity);
        }
    }

    #[cfg(test)]
    fn completed_count(&self) -> usize {
        self.completed
            .lock()
            .map(|completed| completed.len())
            .unwrap_or_default()
    }
}

impl Drop for BoundedAiWorker {
    fn drop(&mut self) {
        self.command_tx.take();
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::{Condvar, Mutex};
    use std::thread::ThreadId;
    use std::time::{Duration, Instant};

    use super::*;
    use crate::{
        AiBudget, AiCandidateInput, AiCandidateSetHash, AiCompositionRevision, AiFeature,
        AiFeaturePolicy, AiRequestBuilder, AiRequestId, AiSessionId, HardwareTier, MockProvider,
        PrivacyGuard,
    };

    struct RecordingProvider {
        inner: MockProvider,
        caller_thread: ThreadId,
        ran_off_caller: AtomicBool,
    }

    impl LocalAiProvider for RecordingProvider {
        fn provider_id(&self) -> &'static str {
            self.inner.provider_id()
        }

        fn capabilities(&self) -> &'static [AiFeature] {
            self.inner.capabilities()
        }

        fn health(&self) -> ProviderHealth {
            self.inner.health()
        }

        fn infer(&self, request: &AiRequest) -> Result<AiResponse, AiError> {
            self.ran_off_caller.store(
                std::thread::current().id() != self.caller_thread,
                Ordering::SeqCst,
            );
            self.inner.infer(request)
        }

        fn cancel(&self, identity: AiRequestIdentity) {
            self.inner.cancel(identity);
        }
    }

    struct BlockingProvider {
        inner: MockProvider,
        gate: (Mutex<bool>, Condvar),
        started: (Mutex<bool>, Condvar),
    }

    impl BlockingProvider {
        fn wait_until_started(&self) {
            let (lock, signal) = &self.started;
            let started = lock.lock().expect("started lock");
            let _ = signal
                .wait_timeout_while(started, Duration::from_secs(1), |started| !*started)
                .expect("started signal");
        }

        fn release(&self) {
            let (lock, signal) = &self.gate;
            *lock.lock().expect("gate lock") = true;
            signal.notify_all();
        }
    }

    impl LocalAiProvider for BlockingProvider {
        fn provider_id(&self) -> &'static str {
            self.inner.provider_id()
        }

        fn capabilities(&self) -> &'static [AiFeature] {
            self.inner.capabilities()
        }

        fn health(&self) -> ProviderHealth {
            self.inner.health()
        }

        fn infer(&self, request: &AiRequest) -> Result<AiResponse, AiError> {
            let (started_lock, started_signal) = &self.started;
            *started_lock.lock().expect("started lock") = true;
            started_signal.notify_all();

            let (gate_lock, gate_signal) = &self.gate;
            let released = gate_lock.lock().expect("gate lock");
            let _released = gate_signal
                .wait_while(released, |released| !*released)
                .expect("gate signal");
            self.inner.infer(request)
        }

        fn cancel(&self, identity: AiRequestIdentity) {
            self.inner.cancel(identity);
        }
    }

    fn request(request_id: u64) -> AiRequest {
        let candidates = vec![AiCandidateInput::new("candidate", 0)];
        let identity = AiRequestIdentity::new(
            AiSessionId::from_u128(1),
            AiRequestId::new(request_id),
            AiCompositionRevision::new(request_id),
            AiCandidateSetHash::from_ordered_texts(["candidate"]),
        );
        AiRequestBuilder::new(
            identity,
            AiFeature::CandidateRerank,
            "zh-Hans",
            HardwareTier::Tier1,
            AiBudget::for_feature(AiFeature::CandidateRerank),
        )
        .with_raw_pinyin("candidate")
        .with_base_candidates(candidates)
        .build(&PrivacyGuard, AiFeaturePolicy::approved_model_enabled(true))
        .expect("request")
    }

    fn wait_for(worker: &BoundedAiWorker, identity: AiRequestIdentity) -> AiWorkerCompletion {
        let deadline = Instant::now() + Duration::from_secs(1);
        loop {
            if let Some(completion) = worker.take_completed(identity) {
                return completion;
            }
            assert!(Instant::now() < deadline, "worker completion timed out");
            std::thread::sleep(Duration::from_millis(2));
        }
    }

    #[test]
    fn provider_runs_off_the_submitting_thread() {
        let provider = Arc::new(RecordingProvider {
            inner: MockProvider::available(),
            caller_thread: std::thread::current().id(),
            ran_off_caller: AtomicBool::new(false),
        });
        let worker = BoundedAiWorker::new(provider.clone()).expect("worker");
        let request = request(1);
        let identity = request.identity();
        assert_eq!(worker.try_submit(request), AiSubmitStatus::Accepted);
        assert!(wait_for(&worker, identity).into_result().is_ok());
        assert!(provider.ran_off_caller.load(Ordering::SeqCst));
    }

    #[test]
    fn saturated_queue_drops_optional_work_without_blocking() {
        let provider = Arc::new(BlockingProvider {
            inner: MockProvider::available(),
            gate: (Mutex::new(false), Condvar::new()),
            started: (Mutex::new(false), Condvar::new()),
        });
        let worker = BoundedAiWorker::with_capacities(provider.clone(), 1, 4).expect("worker");
        assert_eq!(worker.try_submit(request(1)), AiSubmitStatus::Accepted);
        provider.wait_until_started();
        assert_eq!(worker.try_submit(request(2)), AiSubmitStatus::Accepted);
        assert_eq!(worker.try_submit(request(3)), AiSubmitStatus::QueueFull);
        provider.release();
    }

    #[test]
    fn completed_results_are_bounded_and_cancelled_results_are_removed() {
        let worker = BoundedAiWorker::with_capacities(Arc::new(MockProvider::available()), 4, 1)
            .expect("worker");
        let first = request(1);
        let first_identity = first.identity();
        assert_eq!(worker.try_submit(first), AiSubmitStatus::Accepted);
        let deadline = Instant::now() + Duration::from_secs(1);
        while worker.completed_count() == 0 {
            assert!(Instant::now() < deadline, "first completion timed out");
            std::thread::sleep(Duration::from_millis(2));
        }

        let second = request(2);
        let second_identity = second.identity();
        assert_eq!(worker.try_submit(second), AiSubmitStatus::Accepted);
        let _ = wait_for(&worker, second_identity);
        assert!(worker.take_completed(first_identity).is_none());

        let third = request(3);
        let third_identity = third.identity();
        assert_eq!(worker.try_submit(third), AiSubmitStatus::Accepted);
        worker.cancel(third_identity);
        assert!(worker.take_completed(third_identity).is_none());
    }
}
