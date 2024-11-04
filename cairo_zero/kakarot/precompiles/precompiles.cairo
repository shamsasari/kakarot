%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.math_cmp import is_nn, is_not_zero, is_in_range
from starkware.starknet.common.syscalls import library_call
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.memcpy import memcpy

from kakarot.interfaces.interfaces import ICairo1Helpers
from kakarot.storages import Kakarot_cairo1_helpers_class_hash
from kakarot.errors import Errors
from kakarot.precompiles.blake2f import PrecompileBlake2f
from kakarot.precompiles.kakarot_precompiles import KakarotPrecompiles
from kakarot.precompiles.identity import PrecompileIdentity
from kakarot.precompiles.ec_recover import PrecompileEcRecover
from kakarot.precompiles.p256verify import PrecompileP256Verify
from kakarot.precompiles.ripemd160 import PrecompileRIPEMD160
from kakarot.precompiles.sha256 import PrecompileSHA256
from kakarot.precompiles.precompiles_helpers import (
    PrecompilesHelpers,
    LAST_ETHEREUM_PRECOMPILE_ADDRESS,
    FIRST_ROLLUP_PRECOMPILE_ADDRESS,
    FIRST_KAKAROT_PRECOMPILE_ADDRESS,
)
from utils.utils import Helpers

// @title Precompile related functions.
namespace Precompiles {
    // @notice Executes associated function of precompiled evm_address.
    // @dev This function uses an internal jump table to execute the corresponding precompile impmentation.
    // @param precompile_address The precompile evm_address.
    // @param input_len The length of the input array.
    // @param input The input array.
    // @param caller_address The address of the caller of the precompile. Delegatecall rules apply.
    // @param message_address The address being executed in the current message.
    // @return output_len The output length.
    // @return output The output array.
    // @return gas_used The gas usage of precompile.
    // @return reverted The reverted code in {0(success), REVERTED, EXCEPTIONAL_HALT}.
    func exec_precompile{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
    }(
        precompile_address: felt,
        input_len: felt,
        input: felt*,
        caller_address: felt,
        message_address: felt,
    ) -> (output_len: felt, output: felt*, gas_used: felt, reverted: felt) {
        let is_eth_precompile = is_nn(LAST_ETHEREUM_PRECOMPILE_ADDRESS - precompile_address);
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
        jmp eth_precompile if is_eth_precompile != 0;

        let is_rollup_precompile_ = PrecompilesHelpers.is_rollup_precompile(precompile_address);
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
        jmp rollup_precompile if is_rollup_precompile_ != 0;

        let is_kakarot_precompile_ = PrecompilesHelpers.is_kakarot_precompile(precompile_address);
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
        jmp kakarot_precompile if is_kakarot_precompile_ != 0;
        jmp unauthorized_call;

        eth_precompile:
        tempvar index = precompile_address;
        jmp call_precompile;

        rollup_precompile:
        tempvar index = (LAST_ETHEREUM_PRECOMPILE_ADDRESS + 1) + (
            precompile_address - FIRST_ROLLUP_PRECOMPILE_ADDRESS
        );
        jmp call_precompile;

        unauthorized_call:
        // Prepare arguments if none of the above conditions are met
        [ap] = syscall_ptr, ap++;
        [ap] = pedersen_ptr, ap++;
        [ap] = range_check_ptr, ap++;
        [ap] = bitwise_ptr, ap++;
        call unauthorized_precompile;
        ret;

        call_precompile:
        // Compute the corresponding offset in the jump table:
        // count 1 for "next line" and 3 steps per index: call, precompile, ret
        tempvar offset = 1 + 3 * index;

        // Prepare arguments
        [ap] = syscall_ptr, ap++;
        [ap] = pedersen_ptr, ap++;
        [ap] = range_check_ptr, ap++;
        [ap] = bitwise_ptr, ap++;
        [ap] = precompile_address, ap++;
        [ap] = input_len, ap++;
        [ap] = input, ap++;

        // call precompile precompile_address
        jmp rel offset;
        call unknown_precompile;  // 0x0
        ret;
        call PrecompileEcRecover.run;  // 0x1
        ret;
        call external_precompile;  // 0x2
        ret;
        call PrecompileRIPEMD160.run;  // 0x3
        ret;
        call PrecompileIdentity.run;  // 0x4
        ret;
        call not_implemented_precompile;  // 0x5
        ret;
        call external_precompile;  // 0x6
        ret;
        call external_precompile;  // 0x7
        ret;
        call not_implemented_precompile;  // 0x8
        ret;
        call PrecompileBlake2f.run;  // 0x9
        ret;
        call not_implemented_precompile;  // 0x0a: POINT_EVALUATION_PRECOMPILE
        ret;
        // Rollup precompiles. Offset must have been computed appropriately,
        // based on the address of the precompile and the last ethereum precompile
        call PrecompileP256Verify.run;  // offset 0x0b: precompile 0x100
        ret;

        kakarot_precompile:
        let is_call_authorized_ = PrecompilesHelpers.is_call_authorized(
            precompile_address, caller_address, message_address
        );
        tempvar is_not_authorized = 1 - is_call_authorized_;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
        jmp unauthorized_call if is_not_authorized != 0;

        tempvar index = precompile_address - FIRST_KAKAROT_PRECOMPILE_ADDRESS;
        tempvar offset = 1 + 3 * index;

        // Prepare arguments
        [ap] = syscall_ptr, ap++;
        [ap] = pedersen_ptr, ap++;
        [ap] = range_check_ptr, ap++;
        [ap] = bitwise_ptr, ap++;
        [ap] = input_len, ap++;
        [ap] = input, ap++;
        [ap] = caller_address, ap++;

        // Kakarot precompiles. Offset must have been computed appropriately,
        // based on the total number of kakarot precompiles
        jmp rel offset;
        call KakarotPrecompiles.cairo_call_precompile;  // offset 0x0c: precompile 0x75001
        ret;
        call KakarotPrecompiles.cairo_message;  // offset 0x0d: precompile 0x75002
        ret;
        call KakarotPrecompiles.cairo_multicall_precompile;  // offset 0x0e: precompile 0x75003
        ret;
        call KakarotPrecompiles.cairo_call_precompile;  // offset 0x0f: precompile 0x75004
        ret;
    }

    // @notice A placeholder for attempts to call a precompile without permissions
    // @dev Halts execution with an unauthorized precompile error.
    // @return output_len The length of the error message.
    // @return output The error message.
    // @return gas_used The gas used (always 0 for this function).
    // @return reverted The reverted code (EXCEPTIONAL_HALT).
    func unauthorized_precompile{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
    }() -> (output_len: felt, output: felt*, gas_used: felt, reverted: felt) {
        let (revert_reason_len, revert_reason) = Errors.unauthorizedPrecompile();
        return (revert_reason_len, revert_reason, 0, Errors.EXCEPTIONAL_HALT);
    }

    // @notice A placeholder for precompiles that don't exist.
    // @dev Halts execution with an unknown precompile error.
    // @param evm_address The address of the unknown precompile.
    // @param input_len The length of the input array (unused).
    // @param input The input array (unused).
    // @return output_len The length of the error message.
    // @return output The error message.
    // @return gas_used The gas used (always 0 for this function).
    // @return reverted The reverted code (EXCEPTIONAL_HALT).
    func unknown_precompile{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
    }(evm_address: felt, input_len: felt, input: felt*) -> (
        output_len: felt, output: felt*, gas_used: felt, reverted: felt
    ) {
        let (revert_reason_len, revert_reason) = Errors.unknownPrecompile(evm_address);
        return (revert_reason_len, revert_reason, 0, Errors.EXCEPTIONAL_HALT);
    }

    // @notice A placeholder for precompiles that are not implemented yet.
    // @dev Halts execution with a not implemented precompile error.
    // @param evm_address The address of the not implemented precompile.
    // @param input_len The length of the input array (unused).
    // @param input The input array (unused).
    // @return output_len The length of the error message.
    // @return output The error message.
    // @return gas_used The gas used (always 0 for this function).
    // @return reverted The reverted code (EXCEPTIONAL_HALT).
    func not_implemented_precompile{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
    }(evm_address: felt, input_len: felt, input: felt*) -> (
        output_len: felt, output: felt*, gas_used: felt, reverted: felt
    ) {
        let (revert_reason_len, revert_reason) = Errors.notImplementedPrecompile(evm_address);
        return (revert_reason_len, revert_reason, 0, Errors.EXCEPTIONAL_HALT);
    }

    // @notice Executes an external precompile using a Cairo 1 helper contract.
    // @dev Calls the library_call_exec_precompile function of the ICairo1Helpers interface.
    // @param evm_address The address of the external precompile.
    // @param input_len The length of the input array.
    // @param input The input array.
    // @return output_len The length of the output data.
    // @return output The output data.
    // @return gas_used The gas used by the precompile execution.
    // @return reverted 0 if successful, EXCEPTIONAL_HALT if execution failed.
    func external_precompile{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
    }(evm_address: felt, input_len: felt, input: felt*) -> (
        output_len: felt, output: felt*, gas_used: felt, reverted: felt
    ) {
        alloc_locals;
        let (implementation) = Kakarot_cairo1_helpers_class_hash.read();
        let (calldata: felt*) = alloc();
        assert [calldata] = evm_address;
        assert [calldata + 1] = input_len;
        memcpy(calldata + 2, input, input_len);
        let (
            success, gas, return_data_len, return_data
        ) = ICairo1Helpers.library_call_exec_precompile(
            class_hash=implementation, address=evm_address, data_len=input_len, data=input
        );
        if (success != FALSE) {
            return (return_data_len, return_data, gas, 0);
        }
        // Precompiles can only revert with exceptions. Thus if the execution failed, it's an error EXCEPTIONAL_HALT.
        return (return_data_len, return_data, 0, Errors.EXCEPTIONAL_HALT);
    }
}
