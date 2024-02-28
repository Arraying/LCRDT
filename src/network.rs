use std::future::Future;
use crate::node::Node;
use serde::{Deserialize, Serialize};
use serde_json;
use strum::IntoEnumIterator;
use tokio::io::AsyncReadExt;
use tokio::io::AsyncWriteExt;
use tokio::net::{TcpListener, TcpStream};
use crate::counter::Counter;

// Types of messages.
#[derive(Serialize, Deserialize)]
pub enum Message<State> {
    RAW(String),
    SYNC(State)
}

// We will make a trait as this will allow us to test things.
pub trait Net<State: Serialize + for<'a> Deserialize<'a>> {
    // Subscribe to incoming messages.
    async fn receive(&self, node: Node, handler: fn(Message<Counter>) -> impl Future<Output=()> + Sized);

    // Send a message to another node.
    async fn send(&self, node: Node, msg: &Message<State>);

    // Broadcast a message to all nodes (including self).
    async fn broadcast(&self, msg: &Message<State>);
}

pub trait NetReceiver<State: Serialize + for<'a> Deserialize<'a>> {
    async fn handle(self, message: Message<State>);
}

struct NetImpl;

impl<State: Serialize + for<'a> Deserialize<'a>> Net<State> for NetImpl {
    async fn receive(&self, node: Node, handler: fn(Message<Counter>) -> impl Future<Output=()> + Sized) {
        let listener = TcpListener::bind(node.get_addr()).await.unwrap();
        tokio::spawn(async move {
            println!("Accepting connections!");
            let (mut socket, _) = listener.accept().await.unwrap();
            tokio::spawn(async move {
                let mut data: Vec<u8> = Vec::new();
                socket.read_to_end(&mut data).await.unwrap();
                let msg: Message<State> = serde_json::from_slice(&data)
                    .expect("Could not deserialize message");
                handler(&msg)
            });
        });
    }

    async fn send(&self, node: Node, msg: &Message<State>) {
        // Could be sender is offline, in which case we drop.
        if let Ok(mut stream) = TcpStream::connect(node.get_addr()).await {
            let mut data = serde_json::to_vec(&msg)
                .expect("Could not serialize message");
            data.push(b'\n');
            stream.write_all(&data).await.unwrap();
            stream.shutdown().await.unwrap()
        }
    }

    async fn broadcast(&self, msg: &Message<State>) {
        for node in Node::iter() {
            self.send(node, msg).await;
        }
    }
}

pub fn real_network<State: Serialize + for<'a> Deserialize<'a>>() -> impl Net<State> {
    return NetImpl{}
}
