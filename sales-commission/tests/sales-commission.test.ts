import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Test dynamic commission rates based on performance",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user1 = accounts.get('wallet_1')!;
        
        // Setup - initialize tiers
        let block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'initialize-tiers', [], deployer.address),
            Tx.contractCall('sales-commission', 'register-salesperson', 
                [types.principal(user1.address), types.ascii("Alice")], deployer.address)
        ]);
        
        // Verify default performance score is 50
        let salesperson = chain.callReadOnlyFn('sales-commission', 'get-salesperson', 
            [types.principal(user1.address)], deployer.address);
        assertEquals(JSON.parse(salesperson.result.replace(/[u]/g, '')).value.performance_score, 50);
        
        // Update performance metrics
        block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'update-performance-metric', 
                [types.principal(user1.address), types.ascii("sales_velocity"), types.uint(80)], 
                deployer.address),
            Tx.contractCall('sales-commission', 'update-performance-metric', 
                [types.principal(user1.address), types.ascii("customer_satisfaction"), types.uint(90)], 
                deployer.address),
            Tx.contractCall('sales-commission', 'update-performance-metric', 
                [types.principal(user1.address), types.ascii("deal_size"), types.uint(70)], 
                deployer.address)
        ]);
        
        // Verify performance score is now higher
        salesperson = chain.callReadOnlyFn('sales-commission', 'get-salesperson', 
            [types.principal(user1.address)], deployer.address);
        const newScore = JSON.parse(salesperson.result.replace(/[u]/g, '')).value.performance_score;
        console.log("New performance score:", newScore);
        assertEquals(newScore > 50, true);
        
        // Record a sale with high performance score
        block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'record-sale', 
                [types.principal(user1.address), types.uint(5000)], deployer.address)
        ]);
        
        // Verify commission is higher than the base 3% (should include performance bonus)
        const expectedBaseCommission = 5000 * 0.03; // 150
        const actualCommission = parseInt(block.receipts[0].result.replace(/[\(\)ok u]/g, ''));
        console.log("Commission with performance bonus:", actualCommission);
        assertEquals(actualCommission > expectedBaseCommission, true);
    },
});

Clarinet.test({
    name: "Test dispute resolution system",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user1 = accounts.get('wallet_1')!;
        
        // Setup - initialize tiers, register salesperson, record a sale
        let block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'initialize-tiers', [], deployer.address),
            Tx.contractCall('sales-commission', 'register-salesperson', 
                [types.principal(user1.address), types.ascii("Alice")], deployer.address),
            Tx.contractCall('sales-commission', 'record-sale', 
                [types.principal(user1.address), types.uint(10000)], deployer.address)
        ]);
        
        // File a dispute
        block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'file-dispute', 
                [types.uint(1), types.ascii("Commission is too low")], user1.address)
        ]);
        
        // Verify dispute was created
        assertEquals(block.receipts[0].result, '(ok u1)');
        
        // Check dispute details
        let dispute = chain.callReadOnlyFn('sales-commission', 'get-dispute', 
            [types.uint(1)], deployer.address);
        const disputeData = JSON.parse(dispute.result.replace(/[u]/g, ''));
        assertEquals(disputeData.value.status, "pending");
        
        // Get original commission amount
        const originalCommission = parseInt(disputeData.value.original_commission);
        
        // Resolve the dispute with a higher commission
        const adjustedCommission = originalCommission + 100;
        block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'resolve-dispute', 
                [types.uint(1), 
                 types.ascii("resolved"), 
                 types.ascii("Adjusted due to special circumstances"), 
                 types.uint(adjustedCommission)], 
                deployer.address)
        ]);
        
        // Verify dispute was resolved
        assertEquals(block.receipts[0].result, '(ok true)');
        
        // Check the adjusted commission was applied
        let salesperson = chain.callReadOnlyFn('sales-commission', 'get-salesperson', 
            [types.principal(user1.address)], deployer.address);
        const pendingCommission = JSON.parse(salesperson.result.replace(/[u]/g, '')).value.pending_commission;
        
        // The pending commission should now include the adjustment
        assertEquals(pendingCommission, adjustedCommission);
    },
});

Clarinet.test({
    name: "Test CRM integration",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user1 = accounts.get('wallet_1')!;
        
        // Setup - initialize tiers, register salesperson
        let block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'initialize-tiers', [], deployer.address),
            Tx.contractCall('sales-commission', 'register-salesperson', 
                [types.principal(user1.address), types.ascii("Alice")], deployer.address)
        ]);
        
        // Register a CRM integration
        block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'register-crm-integration', 
                [types.ascii("Salesforce"), types.ascii("https://api.salesforce.com/webhook")], 
                deployer.address)
        ]);
        
        // Verify CRM was registered
        assertEquals(block.receipts[0].result, '(ok true)');
        
        // Record a sale through the CRM integration
        block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'record-crm-sale', 
                [types.ascii("Salesforce"), 
                 types.principal(user1.address), 
                 types.uint(15000), 
                 types.ascii("SF-12345")], 
                deployer.address)
        ]);
        
        // Verify sale was recorded
        assertEquals(block.receipts[0].result.includes('ok'), true);
        
        // Check that commission was calculated properly
        let salesperson = chain.callReadOnlyFn('sales-commission', 'get-salesperson', 
            [types.principal(user1.address)], deployer.address);
        const pendingCommission = JSON.parse(salesperson.result.replace(/[u]/g, '')).value.pending_commission;
        
        // With 15000 in sales, we should be in Silver tier (5%)
        // Base commission would be 15000 * 0.05 = 750
        // There might be performance bonus too
        assertEquals(pendingCommission >= 750, true);
        
        // Update CRM sync status
        block = chain.mineBlock([
            Tx.contractCall('sales-commission', 'update-crm-sync', 
                [types.ascii("Salesforce")], 
                deployer.address)
        ]);
        
        // Verify sync was updated
        assertEquals(block.receipts[0].result, '(ok true)');
    },
});
