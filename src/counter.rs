use serde::{Deserialize, Serialize};
use crate::network::{Message};

#[derive(Serialize, Deserialize)]
pub struct Counter;

impl Counter {
    pub async fn handle(&mut self, _msg: Message<Counter>) {
        println!("Received message!");
    }
}
