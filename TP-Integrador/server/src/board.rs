use std::collections::{HashMap, hash_map::Entry};

pub struct Board {
    board: [[Slot; 10]; 10],
    boats_placed: HashMap<BoatLength, u8>,
    boats_to_place: Vec<BoatLength>,
    boat_idx: usize,
    hit_count: usize,
}

#[derive(Default, Clone, Copy)]
#[repr(u8)]
pub enum Slot {
    #[default]
    Empty = 0,
    Boat = 1,
    Hit = 2,
    Missed = 3,
}

#[repr(u8)]
#[derive(Eq, Hash, PartialEq, Clone, Copy, Debug)]
pub enum BoatLength {
    Five = 5,
    Four = 4,
    Three = 3,
    Two = 2,
}

impl BoatLength {
    pub fn from_length(length: u8) -> Option<Self> {
        match length {
            5 => Some(Self::Five),
            4 => Some(Self::Four),
            3 => Some(Self::Three),
            2 => Some(Self::Two),
            _ => None,
        }
    }
}

impl Default for Board {
    fn default() -> Self {
        Self {
            board: Default::default(),
            boats_placed: HashMap::new(),
            boats_to_place: vec![
                BoatLength::Five,
                BoatLength::Four,
                BoatLength::Three,
                BoatLength::Three,
                BoatLength::Two,
                BoatLength::Two,
            ],
            boat_idx: 0,
            hit_count: 0,
        }
    }
}

impl Board {
    pub fn get_hit(&mut self, x: u8, y: u8) {
        let slot = &mut self.board[x as usize][y as usize];

        match slot {
            Slot::Empty => *slot = Slot::Missed,
            Slot::Boat => {
                *slot = Slot::Hit;
                self.hit_count += 1;
            }
            Slot::Hit => {
                // This should be imposible
                eprintln!("Hit a slot twice")
            }
            Slot::Missed => {
                // This should be imposible
                eprintln!("Hit a slot twice")
            }
        }
    }

    pub fn lost(&self) -> bool {
        self.hit_count == 19
    }

    pub fn place_boat(&mut self, x1: u8, y1: u8, x2: u8, y2: u8) {
        if x1 >= 10 || x2 >= 10 || y1 >= 10 || y2 >= 10 {
            eprintln!("The player tried to place a boat outside the board bounds");
            return;
        }

        // TODO: DRY
        // The boat is placed horizontally
        let Some(expected_boat_length) = self.boats_to_place.get(self.boat_idx) else {
            eprintln!("The player tried to place when there are no more boats to place");
            return;
        };
        if x1 == x2 {
            // The length will be determined by the diff in Y values
            let Some(boat_length) = BoatLength::from_length(y1.abs_diff(y2) + 1) else {
                eprintln!("The player tried to place a boat with an invalid length");
                return;
            };
            if boat_length != *expected_boat_length {
                eprintln!("The player tried to place a boat with an unexpected length");
                return;
            }
            // TODO this function has a bunch of repeated logic that can probably be abstracted into a function
            match boat_length {
                BoatLength::Five => {
                    // We can only have 1 5 length boat so if the hashmap does not have the key we don't do anything
                    if let Entry::Vacant(entry) = self.boats_placed.entry(BoatLength::Five) {
                        for i in 0..boat_length as u8 {
                            // If either of the slots in is already a boat the placement is invalid
                            // and we return
                            if let Slot::Boat = self.board[x1 as usize][(y1 + i) as usize] {
                                return;
                            }
                        }
                        // We are certain that the boat will fit, we modify the board
                        for i in 0..boat_length as u8 {
                            self.board[x1 as usize][(y1 + i) as usize] = Slot::Boat;
                        }
                        entry.insert(1);
                    }
                }
                BoatLength::Four => {
                    // We can only have 1 4 length boat so if the hashmap does not have the key we don't do anything
                    if let Entry::Vacant(entry) = self.boats_placed.entry(BoatLength::Four) {
                        for i in 0..boat_length as u8 {
                            // If either of the slots in is already a boat the placement is invalid
                            // and we return
                            if let Slot::Boat = self.board[x1 as usize][(y1 + i) as usize] {
                                return;
                            }
                        }
                        // We are certain that the boat will fit, we modify the board
                        for i in 0..boat_length as u8 {
                            self.board[x1 as usize][(y1 + i) as usize] = Slot::Boat;
                        }
                        entry.insert(1);
                    }
                }
                BoatLength::Three => {
                    // We can have 2 3 length boats so we have to check the hashmap for the current amount
                    let count = self
                        .boats_placed
                        .entry(BoatLength::Three)
                        .or_insert_with(|| 0);
                    if *count < 2_u8 {
                        for i in 0..boat_length as u8 {
                            // If either of the slots in is already a boat the placement is invalid
                            // and we return
                            if let Slot::Boat = self.board[x1 as usize][(y1 + i) as usize] {
                                return;
                            }
                        }
                        // We are certain that the boat will fit, we modify the board
                        for i in 0..boat_length as u8 {
                            self.board[x1 as usize][(y1 + i) as usize] = Slot::Boat;
                        }
                        *count += 1;
                    }
                }
                BoatLength::Two => {
                    // We can have 2 2 length boats so we have to check the hashmap for the current amount
                    let count = self
                        .boats_placed
                        .entry(BoatLength::Two)
                        .or_insert_with(|| 0);
                    if *count < 2_u8 {
                        for i in 0..boat_length as u8 {
                            // If either of the slots in is already a boat the placement is invalid
                            // and we return
                            if let Slot::Boat = self.board[x1 as usize][(y1 + i) as usize] {
                                return;
                            }
                        }
                        // We are certain that the boat will fit, we modify the board
                        for i in 0..boat_length as u8 {
                            self.board[x1 as usize][(y1 + i) as usize] = Slot::Boat;
                        }
                        *count += 1;
                    }
                }
            }
            self.boat_idx += 1;
        } else if y1 == y2 {
            // The boat is placed vertically
            // The length will be determined by the diff in X values
            let Some(boat_length) = BoatLength::from_length(x1.abs_diff(x2) + 1) else {
                eprintln!("The player tried to place a boat with an invalid length");
                return;
            };
            if boat_length != *expected_boat_length {
                eprintln!("The player tried to place a boat with an unexpected length");
                return;
            }
            match boat_length {
                BoatLength::Five => {
                    // We can only have 1 5 length boat so if the hashmap does not have the key we don't do anything
                    if let Entry::Vacant(entry) = self.boats_placed.entry(BoatLength::Five) {
                        for i in 0..boat_length as u8 {
                            // If either of the slots in is already a boat the placement is invalid
                            // and we return
                            if let Slot::Boat = self.board[(x1 + i) as usize][y1 as usize] {
                                return;
                            }
                        }
                        // We are certain that the boat will fit, we modify the board
                        for i in 0..boat_length as u8 {
                            self.board[(x1 + i) as usize][y1 as usize] = Slot::Boat;
                        }
                        entry.insert(1);
                    }
                }
                BoatLength::Four => {
                    // We can only have 1 4 length boat so if the hashmap does not have the key we don't do anything
                    if let Entry::Vacant(entry) = self.boats_placed.entry(BoatLength::Four) {
                        for i in 0..boat_length as u8 {
                            // If either of the slots in is already a boat the placement is invalid
                            // and we return
                            if let Slot::Boat = self.board[(x1 + i) as usize][y1 as usize] {
                                return;
                            }
                        }
                        // We are certain that the boat will fit, we modify the board
                        for i in 0..boat_length as u8 {
                            self.board[(x1 + i) as usize][y1 as usize] = Slot::Boat;
                        }
                        entry.insert(1);
                    }
                }
                BoatLength::Three => {
                    // We can have 2 3 length boats so we have to check the hashmap for the current amount
                    let count = self
                        .boats_placed
                        .entry(BoatLength::Three)
                        .or_insert_with(|| 0);
                    if *count < 2_u8 {
                        for i in 0..boat_length as u8 {
                            // If either of the slots in is already a boat the placement is invalid
                            // and we return
                            if let Slot::Boat = self.board[(x1 + i) as usize][y1 as usize] {
                                return;
                            }
                        }
                        // We are certain that the boat will fit, we modify the board
                        for i in 0..boat_length as u8 {
                            self.board[(x1 + i) as usize][y1 as usize] = Slot::Boat;
                        }
                        *count += 1;
                    }
                }
                BoatLength::Two => {
                    // We can have 2 2 length boats so we have to check the hashmap for the current amount
                    let count = self
                        .boats_placed
                        .entry(BoatLength::Two)
                        .or_insert_with(|| 0);
                    if *count < 2_u8 {
                        for i in 0..boat_length as u8 {
                            // If either of the slots in is already a boat the placement is invalid
                            // and we return
                            if let Slot::Boat = self.board[(x1 + i) as usize][y1 as usize] {
                                return;
                            }
                        }
                        // We are certain that the boat will fit, we modify the board
                        for i in 0..boat_length as u8 {
                            self.board[(x1 + i) as usize][y1 as usize] = Slot::Boat;
                        }
                        *count += 1;
                    }
                }
            }
            self.boat_idx += 1;
        } else {
            //The boat is placed diagonally not valid
            eprintln!("Tried to place a boat diagonally");
        }
    }

    pub fn all_boats_placed(&self) -> bool {
        if !self.boats_placed.contains_key(&BoatLength::Five) {
            return false;
        }
        if !self.boats_placed.contains_key(&BoatLength::Four) {
            return false;
        }
        let Some(three_count) = self.boats_placed.get(&BoatLength::Three) else {
            return false;
        };
        if *three_count != 2 {
            return false;
        }
        let Some(two_count) = self.boats_placed.get(&BoatLength::Two) else {
            return false;
        };
        if *two_count != 2 {
            return false;
        }
        true
    }

    pub fn next_boat(&self) -> Option<&BoatLength> {
        self.boats_to_place.get(self.boat_idx)
    }

    pub fn to_vec(&self) -> Vec<u8> {
        self.board
            .iter()
            .flatten()
            .map(|slot| (*slot) as u8)
            .collect()
    }
}
