use ckb_std::error::SysError;

#[cfg(test)]
extern crate alloc;

#[repr(i8)]
pub enum Error {
    IndexOutOfBound = 1,
    ItemMissing,
    LengthNotEnough,
    Encoding,
    WaitFailure,
    InvalidFd,
    OtherEndClosed,
    MaxVmsSpawned,
    MaxFdsCreated, 
    CarrotAttack,
}

impl From<SysError> for Error {
    fn from(value: SysError) -> Self {
        match value {
            SysError::IndexOutOfBound => Self::IndexOutOfBound,
            SysError::ItemMissing => Self::ItemMissing,
            SysError::LengthNotEnough(_) => Self::LengthNotEnough,
            SysError::Encoding => Self::Encoding,
            SysError::WaitFailure => Self::WaitFailure,
            SysError::InvalidFd => Self::InvalidFd,
            SysError::OtherEndClosed => Self::OtherEndClosed,
            SysError::MaxVmsSpawned => Self::MaxVmsSpawned,
            SysError::MaxFdsCreated => Self::MaxFdsCreated,
            SysError::Unknown(err_code) => panic!("Unexpected sys error {}", err_code),
        }
    }
}