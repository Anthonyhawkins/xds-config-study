{
    "load_balancing_method": "ROUND_ROBIN",
    "timeout": "3s",    
    "distribution": {
        // Primary
        "eu-central": {
            "priority": 0,
            "weight": 100
        }

        // Failover
        "us-east-1": {
            "priority": 0,
            "weight": 80,   
        },
        "us-west-2": {
            "priority": 0,
            "weight": 20
        },

    }
}

