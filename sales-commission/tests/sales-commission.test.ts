import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Ensure that owner can initialize tiers",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'initialize-tiers', [], deployer.address)
        ]);
        
        // Assert that the transaction was successful
        assertEquals(block.receipts[0].result, '(ok true)');
        
        // Verify that tier 1 (Bronze) was properly set
        let tier1 = chain.callReadOnlyFn('sales-commission', 'get-commission-tier', [types.uint(1)], deployer.address);
        assertEquals(tier1.result, '(some {commission-rate: u300, min-sales: u0, name: "Bronze"})');
    },
});

Clarinet.test({
    name: "Ensure that only owner can register salespeople",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user1 = accounts.get('wallet_1')!;
        const user2 = accounts.get('wallet_2')!;
        
        // Owner registers a salesperson - should succeed
        let block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'register-salesperson', 
                [types.principal(user1.address), types.ascii("Alice")], 
                deployer.address)
        ]);
        
        assertEquals(block.receipts[0].result, '(ok true)');
        
        // Non-owner tries to register a salesperson - should fail
        block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'register-salesperson', 
                [types.principal(user2.address), types.ascii("Bob")], 
                user1.address)
        ]);
        
        // Assert that the transaction failed with unauthorized error
        assertEquals(block.receipts[0].result, '(err u100)');
        
        // Verify that the first salesperson was properly registered
        let salesperson = chain.callReadOnlyFn('sales-commission', 'get-salesperson', 
            [types.principal(user1.address)], deployer.address);
        
        assertEquals(salesperson.result, 
            '(some {active: true, name: "Alice", pending-commission: u0, total-sales: u0})');
    },
});

Clarinet.test({
    name: "Ensure sales are recorded and commissions calculated correctly",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user1 = accounts.get('wallet_1')!;
        
        // Initialize tiers
        chain.mineBlock([
            Tx.contractCall('sales-commission', 'initialize-tiers', [], deployer.address)
        ]);
        
        // Register a salesperson
        chain.mineBlock([
            Tx.contractCall('sales-commission', 'register-salesperson', 
                [types.principal(user1.address), types.ascii("Alice")], 
                deployer.address)
        ]);
        
        // Record a sale of 5000
        let block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'record-sale', 
                [types.principal(user1.address), types.uint(5000)], 
                deployer.address)
        ]);
        
        // 5000 * 3% = 150
        assertEquals(block.receipts[0].result, '(ok u150)');
        
        // Check salesperson's updated stats
        let salesperson = chain.callReadOnlyFn('sales-commission', 'get-salesperson', 
            [types.principal(user1.address)], deployer.address);
        
        assertEquals(salesperson.result, 
            '(some {active: true, name: "Alice", pending-commission: u150, total-sales: u5000})');
        
        // Record another sale to push into the next tier
        block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'record-sale', 
                [types.principal(user1.address), types.uint(10000)], 
                deployer.address)
        ]);
        
        // Sale is in Silver tier (5%) - 10000 * 5% = 500
        assertEquals(block.receipts[0].result, '(ok u500)');
        
        // Check that total sales and pending commission updated correctly
        salesperson = chain.callReadOnlyFn('sales-commission', 'get-salesperson', 
            [types.principal(user1.address)], deployer.address);
        
        assertEquals(salesperson.result, 
            '(some {active: true, name: "Alice", pending-commission: u650, total-sales: u15000})');
    },
});

Clarinet.test({
    name: "Test commission payout function",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user1 = accounts.get('wallet_1')!;
        
        // Setup - initialize tiers, register salesperson, record a sale
        chain.mineBlock([
            Tx.contractCall('sales-commission', 'initialize-tiers', [], deployer.address),
            Tx.contractCall('sales-commission', 'register-salesperson', 
                [types.principal(user1.address), types.ascii("Alice")], 
                deployer.address),
            Tx.contractCall('sales-commission', 'record-sale', 
                [types.principal(user1.address), types.uint(10000)], 
                deployer.address)
        ]);
        
        // Payout commission
        let block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'payout-commission', 
                [types.principal(user1.address)], 
                deployer.address)
        ]);
        
        // Should return the amount paid out (10000 * 3% = 300)
        assertEquals(block.receipts[0].result, '(ok u300)');
        
        // Verify that pending commission is now zero
        let salesperson = chain.callReadOnlyFn('sales-commission', 'get-salesperson', 
            [types.principal(user1.address)], deployer.address);
        
        assertEquals(salesperson.result, 
            '(some {active: true, name: "Alice", pending-commission: u0, total-sales: u10000})');
        
        // Attempting to payout again with no pending commission should fail
        block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'payout-commission', 
                [types.principal(user1.address)], 
                deployer.address)
        ]);
        
        assertEquals(block.receipts[0].result, '(err u101)');
    },
});
