use crate::{verify_and_dump_failed_tx, Loader};
use ckb_testtool::builtin::ALWAYS_SUCCESS;
use ckb_testtool::ckb_types::{bytes::Bytes, core::TransactionBuilder, packed::*, prelude::*};
use ckb_testtool::context::Context;

const MAX_CYCLES: u64 = 10_000_000;

#[test]
fn test_carrot_script() {
    // deploy carrot contract
    let mut context = Context::default();
    let carrot_bin = Loader::default().load_binary("carrot-script");
    let carrot_out_point = context.deploy_cell(carrot_bin);
    let carrot_cell_dep = CellDep::new_builder()
        .out_point(carrot_out_point.clone())
        .build();

    // prepare scripts
    let always_success_out_point = context.deploy_cell(ALWAYS_SUCCESS.clone());
    let lock_script = context
        .build_script(&always_success_out_point.clone(), Default::default())
        .expect("construct lock script error");
    let lock_script_dep = CellDep::new_builder()
        .out_point(always_success_out_point)
        .build();

    // prepare cell deps
    let cell_deps: Vec<CellDep> = vec![lock_script_dep, carrot_cell_dep];

    // prepare cells
    let input_out_point = context.create_cell(
        CellOutput::new_builder()
            .capacity(1000u64.pack())
            .lock(lock_script.clone())
            .build(),
        Bytes::new(),
    );

    let input = CellInput::new_builder()
        .previous_output(input_out_point.clone())
        .build();

    let type_script = context
        .build_script(&carrot_out_point, Bytes::new())
        .expect("construct type script error");

    let outputs = vec![
        CellOutput::new_builder()
            .capacity(500u64.pack())
            .lock(lock_script.clone())
            .type_(Some(type_script.clone()).pack())
            .build(),
        CellOutput::new_builder()
            .capacity(500u64.pack())
            .lock(lock_script)
            .build(),
    ];

    // prepare output cell data
    let outputs_data = vec![Bytes::from("apple"), Bytes::from("orange")];

    // build transaction
    let tx = TransactionBuilder::default()
        .cell_deps(cell_deps)
        .input(input)
        .outputs(outputs)
        .outputs_data(outputs_data.pack())
        .build();

    let tx = tx.as_advanced_builder().build();

    // let cycles = context.verify_tx(&tx, MAX_CYCLES).expect("pass verification");
    let cycles = verify_and_dump_failed_tx(&context, &tx, MAX_CYCLES).expect("pass verification");

    println!("consume cycles: {}", cycles);
}

// // Include your tests here
// // See https://github.com/xxuejie/ckb-native-build-sample/blob/main/tests/src/tests.rs for examples
