use crate::game_server::{GameServer, PendingConnection, Player};
use std::{net::TcpListener, sync::Arc};
mod board;
mod game_server;

fn take_next_connection(queue: &mut Vec<PendingConnection>) -> Option<PendingConnection> {
    while let Some(mut pending) = queue.pop() {
        if pending.refresh() {
            return Some(pending);
        } else {
            eprintln!("Discarded connection while waiting for opponent");
        }
    }
    None
}

fn main() {
    let tcp_server = TcpListener::bind("127.0.0.1:1234").unwrap();
    println!("Accepting connections at 127.0.0.1:1234");
    let mut player_queue: Vec<PendingConnection> = Vec::new();
    loop {
        match tcp_server.accept() {
            Ok((stream, _addr)) => {
                player_queue.push(PendingConnection::new(stream));
                if player_queue.len() >= 2 {
                    if let Some(player_a_pending) = take_next_connection(&mut player_queue) {
                        if let Some(player_b_pending) = take_next_connection(&mut player_queue) {
                            let server = Arc::new(GameServer::default());
                            let server_clone = server.clone();
                            std::thread::spawn(move || {
                                let (stream, buffer) = player_a_pending.into_parts();
                                server.handle_connection(stream, buffer, Player::A)
                            });
                            std::thread::spawn(move || {
                                let (stream, buffer) = player_b_pending.into_parts();
                                server_clone.handle_connection(stream, buffer, Player::B)
                            });
                        } else {
                            player_queue.push(player_a_pending);
                        }
                    }
                }
            }
            Err(e) => {
                eprintln!("Error accepting connection: {e}");
            }
        }
    }
}
