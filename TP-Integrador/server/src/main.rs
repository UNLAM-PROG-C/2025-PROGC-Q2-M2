use crate::game_server::{GameServer, Player};
use std::{net::TcpListener, sync::Arc};
mod board;
mod game_server;

fn main() {
    let tcp_server = TcpListener::bind("127.0.0.1:1234").unwrap();
    println!("Accepting connections at 127.0.0.1:1234");
    let mut player_queue = Vec::new();
    loop {
        match tcp_server.accept() {
            Ok(conn) => {
                player_queue.push(conn);
                // TODO: Check if the connection is still valid before creating the threads
                if player_queue.len() >= 2 {
                    let player_a = player_queue.pop().unwrap();
                    let player_b = player_queue.pop().unwrap();
                    let server = Arc::new(GameServer::default());
                    let server_clone = server.clone();
                    std::thread::spawn(move || server.handle_connection(player_a.0, Player::A));
                    std::thread::spawn(move || {
                        server_clone.handle_connection(player_b.0, Player::B)
                    });
                }
            }
            Err(e) => {
                eprintln!("Error accepting connection: {e}");
            }
        }
    }
}
