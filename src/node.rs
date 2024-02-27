use std::env;
use std::str::FromStr;
use strum::IntoEnumIterator;
use strum_macros::{Display, EnumIter, EnumString};

#[derive(Debug, Display, EnumIter, EnumString)]
pub enum Node {
    ONE,
    TWO,
    THREE
}

impl Node {
    pub fn get_addr(self) -> String {
        String::from(match self {
            Node::ONE => "127.0.0.1:1901",
            Node::TWO => "127.0.0.1:1902",
            Node::THREE => "127.0.0.1:1903",
        })
    }
}

pub fn whoami() -> Node {
    let args: Vec<String> = env::args().collect();
    let possible = Node::iter()
        .map(|x| x.to_string())
        .collect::<Vec<String>>()
        .join(", ");
    if args.len() < 2 {
        panic!("Please provide a node ID, can be one of {}.", possible);
    }
    Node::from_str(&args[1].to_uppercase())
        .expect(format!("Node ID be one of: {}", possible).as_str())
}
