import {
    Clarinet,
    Tx,
    Chain,
    Account,
    types
} from 'https://deno.land/x/clarinet@v1.5.4/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
    name: "Can make a valid deposit",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get("deployer")!;
        const wallet1 = accounts.get("wallet_1")!;
        const amount = 500000; // 0.5 STX

        let block = chain.mineBlock([
            Tx.contractCall(
                "time-locked-savings",
                "deposit",
                [types.uint(amount)],
                wallet1.address
            )
        ]);

        // Assert successful result
        block.receipts[0].result.expectOk();
        
        // Check account info
        const account_info = chain.callReadOnlyFn(
            "time-locked-savings",
            "get-account-info",
            [types.principal(wallet1.address)],
            deployer.address
        );
        
        // Assert account balance matches deposit
        assertEquals(
            account_info.result.expectSome().expectTuple()["balance"],
            types.uint(amount)
        );
    }
});

Clarinet.test({
    name: "Fails with deposit below minimum",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const wallet1 = accounts.get("wallet_1")!;
        const smallAmount = 50000; // 0.05 STX (below MIN_DEPOSIT)

        let block = chain.mineBlock([
            Tx.contractCall(
                "time-locked-savings",
                "deposit",
                [types.uint(smallAmount)],
                wallet1.address
            )
        ]);

        // Assert error result
        block.receipts[0].result.expectErr().expectUint(105); // ERR-INVALID-AMOUNT
    }
});

Clarinet.test({
    name: "Can lock funds for valid period",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get("deployer")!;
        const wallet1 = accounts.get("wallet_1")!;
        const amount = 500000; // 0.5 STX
        const lockPeriod = 100; // 100 blocks

        let block = chain.mineBlock([
            // First deposit
            Tx.contractCall(
                "time-locked-savings",
                "deposit",
                [types.uint(amount)],
                wallet1.address
            ),
            // Then lock
            Tx.contractCall(
                "time-locked-savings",
                "lock-funds",
                [types.uint(lockPeriod)],
                wallet1.address
            )
        ]);

        // Assert successful deposit and lock
        block.receipts[0].result.expectOk();
        block.receipts[1].result.expectOk();
        
        // Check account info
        const account_info = chain.callReadOnlyFn(
            "time-locked-savings",
            "get-account-info",
            [types.principal(wallet1.address)],
            deployer.address
        );
        
        const accountData = account_info.result.expectSome().expectTuple();
        assertEquals(accountData["balance"], types.uint(amount));
        assertEquals(
            accountData["lock-until"], 
            types.uint(block.height + lockPeriod)
        );
    }
});

Clarinet.test({
    name: "Cannot lock funds without deposit",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const wallet1 = accounts.get("wallet_1")!;
        const lockPeriod = 100;

        let block = chain.mineBlock([
            Tx.contractCall(
                "time-locked-savings",
                "lock-funds",
                [types.uint(lockPeriod)],
                wallet1.address
            )
        ]);

        // Assert error for no balance
        block.receipts[0].result.expectErr().expectUint(102); // ERR-NO-BALANCE
    }
});

Clarinet.test({
    name: "Can calculate interest correctly",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get("deployer")!;
        const wallet1 = accounts.get("wallet_1")!;
        const amount = 1000000; // 1 STX
        const lockPeriod = 100; // 100 blocks

        let block = chain.mineBlock([
            Tx.contractCall(
                "time-locked-savings",
                "deposit",
                [types.uint(amount)],
                wallet1.address
            ),
            Tx.contractCall(
                "time-locked-savings",
                "lock-funds",
                [types.uint(lockPeriod)],
                wallet1.address
            )
        ]);

        // Calculate expected interest (5% APR)
        // interest = principal * rate * time / 10000
        const interest = chain.callReadOnlyFn(
            "time-locked-savings",
            "calculate-interest",
            [types.principal(wallet1.address)],
            deployer.address
        );

        // Assert interest is greater than 0
        assert(interest.result.expectUint() > 0);
    }
});
