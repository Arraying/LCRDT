use serde::{Deserialize, Serialize};
use crate::network::{Message, NetReceiver};

#[derive(Serialize, Deserialize)]
pub struct Counter;

impl NetReceiver<Counter> for Counter {
    async fn handle(self, message: Message<Counter>) {
        todo!()
    }
}