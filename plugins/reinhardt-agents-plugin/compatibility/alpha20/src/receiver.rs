//! Application-owned task contract used by the documentation's mock examples.
use std::sync::Arc;

use async_trait::async_trait;
use mockall::automock;
use reinhardt::tasks::{Task, TaskError, TaskExecutor, TaskId, TaskResult};
use uuid::Uuid;

pub struct OrderDto {
    pub id: Uuid,
    pub notification_sent: bool,
}

#[automock]
pub trait OrderRepo: Send + Sync {
    fn get(&self, id: Uuid) -> TaskResult<Option<OrderDto>>;
    fn mark_notified(&self, id: Uuid) -> TaskResult<()>;
}

pub struct SendOrderConfirmation<R: OrderRepo> {
    order_id: Uuid,
    task_id: TaskId,
    repository: Arc<R>,
}

impl<R: OrderRepo> SendOrderConfirmation<R> {
    pub fn new(order_id: Uuid, repository: Arc<R>) -> Self {
        Self {
            order_id,
            task_id: TaskId::new(),
            repository,
        }
    }
}

impl<R: OrderRepo> Task for SendOrderConfirmation<R> {
    fn id(&self) -> TaskId {
        self.task_id
    }
    fn name(&self) -> &str {
        "send_order_confirmation"
    }
}

#[async_trait]
impl<R: OrderRepo> TaskExecutor for SendOrderConfirmation<R> {
    async fn execute(&self) -> TaskResult<()> {
        let order = self
            .repository
            .get(self.order_id)?
            .ok_or_else(|| TaskError::ExecutionFailed("Order not found".into()))?;
        if order.id != self.order_id {
            return Err(TaskError::ExecutionFailed("Order identity mismatch".into()));
        }
        if !order.notification_sent {
            self.repository.mark_notified(self.order_id)?;
        }
        Ok(())
    }
}
