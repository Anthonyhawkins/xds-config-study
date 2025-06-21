{
    "load_balancing_method": "ROUND_ROBIN",
    "timeout": "3s",    
    "distribution": {
        // Primary
        "us-east-1": {
            "priority": 0,
            "weight": 20,   
        },
        "us-west-2": {
            "priority": 0,
            "weight": 80
        },

        // Failover
        "eu-central": {
            "priority": 1,
            "weight": 100
        }

    }
}

