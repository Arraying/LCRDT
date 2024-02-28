use std::{io};
use crate::counter::Counter;
use crate::network::{Message, Net};

mod network;
mod node;
mod counter;

#[tokio::main]
async fn main() {
    // First, we figure out who we are.
    let the_node = node::whoami();
    // Initialized CRDT state.
    let counter = Counter{};
    // Now we can start up our networking.
    let the_net = network::real_network::<Counter>();
    the_net.receive(the_node, handle).await;
    // Run the command prompt loop.
    loop {
        // Get command line input.
        let mut cmd = String::new();
        io::stdin()
            .read_line(&mut cmd)
            .expect("Could not read command!");
        let mut parts = cmd.trim().splitn(2, " ");
        let first = parts.next();
        // What command are we executing?
        if let Some(name) = first {
            match name {
                "bc" => {
                    if let Some(msg) = parts.next() {
                        the_net.broadcast(&Message::RAW(String::from(msg))).await;
                    } else {
                        println!("Please provide a message!")
                    }
                }
                _ => println!("Unknown command '{}'", name)
            }
        } else {
            println!("Please provide a command!");
        }
    }
}
