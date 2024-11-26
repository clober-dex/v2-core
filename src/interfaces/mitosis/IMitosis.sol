// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IMitosis
 * @notice Interface for the main entry point of Mitosis contracts for third-party integrations.
 */
interface IMitosis {
  //====================== NOTE: CONTRACTS ======================//

  /**
   * @notice Sets the delegation manager for the specified account.
   * @param account The account address
   * @param delegationManager_ The address of the delegation manager.
   */
  function setDelegationManager(address account, address delegationManager_) external;

  /**
   * @notice Sets the default delegatee for the specified account.
   * @param account The account address
   * @param defaultDelegatee_ The address of the default delegatee.
   */
  function setDefaultDelegatee(address account, address defaultDelegatee_) external;
}
