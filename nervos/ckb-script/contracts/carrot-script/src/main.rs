#![cfg_attr(not(any(feature = "native-simulator", test)), no_std)]
#![cfg_attr(not(test), no_main)]

use carrot_script::Error;
use ckb_std::{ckb_constants::Source, debug, high_level::load_cell_data};

#[cfg(any(feature = "native-simulator", test))]
extern crate alloc;

#[cfg(not(any(feature = "native-simulator", test)))]
ckb_std::entry!(program_entry);
#[cfg(not(any(feature = "native-simulator", test)))]
ckb_std::default_alloc!();

pub fn program_entry() -> i8 {
    ckb_std::debug!("This is a sample contract!");

    match carrot_forbidden() {
        Ok(_) => 0,
        Err(err) => err as i8,
    }
}

fn carrot_forbidden() -> Result<(), Error> {
    let mut index = 0;

    loop {
        match load_cell_data(index, Source::GroupOutput) {
            Ok(data) => {
                if data.starts_with("carrot".as_bytes()) {
                    return Err(Error::CarrotAttack);
                } else {
                    debug!("Output #{:} has no carrot! Hooray!", index);
                }
            }
            Err(err) => match err {
                ckb_std::error::SysError::IndexOutOfBound => break,
                _ => return Err(Error::from(err)),
            },
        }
        index += 1;
    }

    Ok(())
}
