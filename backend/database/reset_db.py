#!/usr/bin/env python3
"""
Database Reset Script
Drops all tables, recreates schema, and loads seed data
"""

import sys
import argparse
from pathlib import Path
from src.client import DataAPIClient
from src.models import Database
from src.schemas import UserCreate, AccountCreate, PositionCreate
from decimal import Decimal


def drop_all_tables(db: DataAPIClient):
    """Drop all tables in correct order (respecting foreign keys)"""
    print("🗑️  Dropping existing tables...")
    
    # Order matters due to foreign key constraints
    tables_to_drop = [
        'positions',
        'accounts',
        'jobs',
        'instruments',
        'users'
    ]
    
    for table in tables_to_drop:
        try:
            db.execute(f"DROP TABLE IF EXISTS {table} CASCADE")
            print(f"   ✅ Dropped {table}")
        except Exception as e:
            print(f"   ⚠️  Error dropping {table}: {e}")
    
    # Also drop the function
    try:
        db.execute("DROP FUNCTION IF EXISTS update_updated_at_column() CASCADE")
        print(f"   ✅ Dropped update_updated_at_column function")
    except Exception as e:
        print(f"   ⚠️  Error dropping function: {e}")


def create_test_data(db_models: Database, user_id: str = None):
    """Create test user with sample portfolio.
    
    Args:
        db_models: Database models instance
        user_id: Clerk user ID. If not provided, creates a test user 'test_user_001'.
                 If provided, uses the existing user (must already exist in the users table).
    """
    use_existing_user = user_id is not None
    target_user_id = user_id or 'test_user_001'
    
    print(f"\n👤 Creating portfolio for user: {target_user_id}...")
    
    if not use_existing_user:
        # Create test user with Pydantic validation
        user_data = UserCreate(
            clerk_user_id=target_user_id,
            display_name='Test User',
            years_until_retirement=25,
            target_retirement_income=Decimal('100000')
        )
        
        existing = db_models.users.find_by_clerk_id(target_user_id)
        if existing:
            print("   ℹ️  Test user already exists")
        else:
            validated = user_data.model_dump()
            db_models.users.create_user(
                clerk_user_id=validated['clerk_user_id'],
                display_name=validated['display_name'],
                years_until_retirement=validated['years_until_retirement'],
                target_retirement_income=validated['target_retirement_income']
            )
            print("   ✅ Created test user")
    else:
        # Verify the user exists
        existing = db_models.users.find_by_clerk_id(target_user_id)
        if not existing:
            print(f"   ⚠️  User {target_user_id} not found — creating minimal record")
            db_models.users.create_user(
                clerk_user_id=target_user_id,
                display_name='Agentra User',
                years_until_retirement=25,
                target_retirement_income=Decimal('100000')
            )
            print("   ✅ Created user record")
        else:
            print("   ✅ User exists")
    
    # Create accounts with Pydantic validation
    accounts = [
        AccountCreate(
            account_name='401(k)',
            account_purpose='Primary retirement savings',
            cash_balance=Decimal('5000'),
            cash_interest=Decimal('0.045')
        ),
        AccountCreate(
            account_name='Roth IRA',
            account_purpose='Tax-free retirement savings',
            cash_balance=Decimal('1000'),
            cash_interest=Decimal('0.04')
        ),
        AccountCreate(
            account_name='Taxable Brokerage',
            account_purpose='General investment account',
            cash_balance=Decimal('2500'),
            cash_interest=Decimal('0.035')
        )
    ]
    
    user_accounts = db_models.accounts.find_by_user(target_user_id)
    
    if user_accounts:
        print(f"   ℹ️  User already has {len(user_accounts)} accounts")
        account_ids = [acc['id'] for acc in user_accounts]
    else:
        account_ids = []
        for acc_data in accounts:
            validated = acc_data.model_dump()
            acc_id = db_models.accounts.create_account(
                target_user_id,
                account_name=validated['account_name'],
                account_purpose=validated['account_purpose'],
                cash_balance=validated['cash_balance'],
                cash_interest=validated['cash_interest']
            )
            account_ids.append(acc_id)
            print(f"   ✅ Created account: {validated['account_name']}")
    
    # Create positions across accounts
    if account_ids:
        # 401(k) positions — diversified core
        positions_401k = [
            ('SPY', Decimal('100')),   # ~$45,000
            ('QQQ', Decimal('50')),    # ~$20,000
            ('BND', Decimal('200')),   # ~$16,000
            ('VEA', Decimal('150')),   # ~$7,500
            ('GLD', Decimal('25')),    # ~$5,000
        ]
        
        # Roth IRA positions — growth focused
        positions_roth = [
            ('VUG', Decimal('75')),    # ~$25,000
            ('VIG', Decimal('100')),   # ~$18,000
            ('XLK', Decimal('50')),    # ~$10,000
        ]
        
        # Taxable positions — income/dividend
        positions_taxable = [
            ('VTV', Decimal('80')),    # ~$12,000
            ('AGG', Decimal('100')),   # ~$10,000
        ]
        
        all_positions = [
            (0, positions_401k, '401(k)'),
            (1, positions_roth, 'Roth IRA'),
            (2, positions_taxable, 'Taxable Brokerage'),
        ]
        
        for idx, positions, acct_name in all_positions:
            if idx >= len(account_ids):
                break
            account_id = account_ids[idx]
            existing_positions = db_models.positions.find_by_account(account_id)
            
            if existing_positions:
                print(f"   ℹ️  {acct_name} already has {len(existing_positions)} positions")
            else:
                for symbol, quantity in positions:
                    position = PositionCreate(
                        account_id=account_id,
                        symbol=symbol,
                        quantity=quantity
                    )
                    validated = position.model_dump()
                    db_models.positions.add_position(
                        validated['account_id'],
                        validated['symbol'],
                        validated['quantity']
                    )
                    print(f"   ✅ {acct_name}: {quantity} shares of {symbol}")


def main():
    parser = argparse.ArgumentParser(description='Reset Agentra database')
    parser.add_argument('--with-test-data', action='store_true',
                       help='Create user with sample portfolio')
    parser.add_argument('--user-id', type=str, default=None,
                       help='Clerk user ID to seed portfolio for (uses existing user). '
                            'If omitted, creates test_user_001.')
    parser.add_argument('--skip-drop', action='store_true',
                       help='Skip dropping tables (just reload data)')
    args = parser.parse_args()
    
    print("🚀 Database Reset Script")
    print("=" * 50)
    
    # Initialize database
    db = DataAPIClient()
    db_models = Database()
    
    if not args.skip_drop:
        # Drop all tables
        drop_all_tables(db)
        
        # Run migrations
        print("\n📝 Running migrations...")
        import subprocess
        result = subprocess.run(['uv', 'run', 'run_migration.py'], 
                              capture_output=True, text=True)
        
        if result.returncode != 0:
            print("❌ Migration failed!")
            print(result.stderr)
            sys.exit(1)
        else:
            print("✅ Migrations completed")
    
    # Load seed data
    print("\n🌱 Loading seed data...")
    import subprocess
    result = subprocess.run(['uv', 'run', 'seed_data.py'], 
                          capture_output=True, text=True)
    
    if result.returncode != 0:
        print("❌ Seed data failed!")
        print(result.stderr)
        sys.exit(1)
    else:
        # Extract instrument count from output
        if '22/22 instruments loaded' in result.stdout:
            print("✅ Loaded 22 instruments")
        else:
            print("✅ Seed data loaded")
    
    # Create test data if requested
    if args.with_test_data:
        create_test_data(db_models, user_id=args.user_id)
    
    # Final verification
    print("\n🔍 Final verification...")
    
    # Count records
    tables = ['users', 'instruments', 'accounts', 'positions', 'jobs']
    for table in tables:
        result = db.query(f"SELECT COUNT(*) as count FROM {table}")
        count = result[0]['count'] if result else 0
        print(f"   • {table}: {count} records")
    
    print("\n" + "=" * 50)
    print("✅ Database reset complete!")
    
    if args.with_test_data:
        target_user = args.user_id or 'test_user_001'
        print(f"\n📝 Portfolio created for: {target_user}")
        print("   • 3 accounts (401k, Roth IRA, Taxable Brokerage)")
        print("   • 10 positions across accounts")


if __name__ == "__main__":
    main()