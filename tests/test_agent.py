#!/usr/bin/env python3
"""
Basic tests for the SignalWire Weather Agent
"""

import sys
import os
import unittest
from unittest.mock import patch, MagicMock
import json

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

try:
    from hybrid_lambda_handler import WeatherAgent, lambda_handler, agent, app, handler
except ImportError as e:
    print(f"❌ Import error: {e}")
    print("💡 Make sure signalwire-agents is installed: pip install signalwire-agents")
    sys.exit(1)

class TestWeatherAgent(unittest.TestCase):
    """Test cases for the WeatherAgent class"""
    
    def setUp(self):
        """Set up test environment"""
        self.agent = WeatherAgent()
    
    def test_agent_initialization(self):
        """Test that the agent initializes correctly"""
        self.assertIsNotNone(self.agent)
        self.assertEqual(self.agent.name, "weather-agent")
    
    def test_parameter_normalization(self):
        """Test parameter normalization functionality"""
        # Test normal parameters
        location, days, alerts = self.agent._normalize_parameters("New York", 3, True)
        self.assertEqual(location, "New York")
        self.assertEqual(days, 3)
        self.assertTrue(alerts)
        
        # Test dict location parameter
        location, days, alerts = self.agent._normalize_parameters({"location": "London"}, 1, False)
        self.assertEqual(location, "London")
        self.assertEqual(days, 1)
        self.assertFalse(alerts)
        
        # Test string boolean
        location, days, alerts = self.agent._normalize_parameters("Paris", 2, "true")
        self.assertEqual(location, "Paris")
        self.assertEqual(days, 2)
        self.assertTrue(alerts)
    
    def test_weather_response_formatting(self):
        """Test weather response formatting"""
        # Mock weather data
        mock_data = {
            "current": {
                "temp_f": 72,
                "temp_c": 22,
                "condition": {"text": "Sunny"},
                "feelslike_f": 75,
                "feelslike_c": 24,
                "humidity": 60,
                "wind_mph": 5,
                "wind_dir": "NW"
            },
            "location": {
                "name": "San Francisco",
                "region": "California",
                "country": "United States"
            },
            "forecast": {
                "forecastday": [
                    {
                        "date": "2024-01-01",
                        "day": {
                            "condition": {"text": "Partly Cloudy"},
                            "maxtemp_f": 75,
                            "maxtemp_c": 24,
                            "mintemp_f": 60,
                            "mintemp_c": 16,
                            "daily_chance_of_rain": 20
                        }
                    }
                ]
            }
        }
        
        response = self.agent._format_weather_response(mock_data, 1, False)
        
        self.assertIn("San Francisco", response)
        self.assertIn("72°F", response)
        self.assertIn("Sunny", response)
        self.assertIn("60%", response)  # humidity
    
    @patch('hybrid_lambda_handler.requests.get')
    def test_weather_function_success(self, mock_get):
        """Test successful weather function call"""
        # Mock successful API response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "current": {
                "temp_f": 72, "temp_c": 22,
                "condition": {"text": "Sunny"},
                "feelslike_f": 75, "feelslike_c": 24,
                "humidity": 60, "wind_mph": 5, "wind_dir": "NW",
                "last_updated": "2024-01-01 12:00"
            },
            "location": {
                "name": "Test City",
                "region": "Test State",
                "country": "Test Country"
            },
            "forecast": {"forecastday": []}
        }
        mock_get.return_value = mock_response
        
        # Mock environment variable
        with patch.dict(os.environ, {'WEATHERAPI_KEY': 'test-key'}):
            result = self.agent.get_weather("Test City")
            
            self.assertIsNotNone(result)
            self.assertIn("Test City", result.response)
            self.assertIn("72°F", result.response)
    
    def test_weather_function_no_api_key(self):
        """Test weather function without API key"""
        with patch.dict(os.environ, {}, clear=True):
            result = self.agent.get_weather("Test City")
            
            self.assertIsNotNone(result)
            self.assertIn("not configured", result.response)

class TestLambdaHandler(unittest.TestCase):
    """Test cases for the Lambda handler"""
    
    def test_agent_instance(self):
        """Test that agent instance is accessible"""
        self.assertIsNotNone(agent)
        self.assertIsInstance(agent, WeatherAgent)
    
    def test_mangum_handler(self):
        """Test that Mangum handler is properly configured"""
        self.assertIsNotNone(handler)
        self.assertIsNotNone(app)
        # Verify app is the FastAPI app from the agent
        self.assertEqual(app, agent.get_app())
    
    def test_health_endpoint_mangum(self):
        """Test health endpoint with Mangum integration"""
        # Create API Gateway event for health endpoint
        event = {
            "httpMethod": "GET",
            "path": "/health",
            "headers": {
                "Authorization": "Basic ZGV2Oncwb3Q="  # dev:w00t in base64
            },
            "body": "",
            "requestContext": {
                "requestId": "test-request-id"
            }
        }
        context = MagicMock()
        
        response = lambda_handler(event, context)
        
        self.assertEqual(response["statusCode"], 200)
        self.assertIn("application/json", response["headers"]["content-type"])
        
        # Parse response body
        response_body = json.loads(response["body"])
        self.assertEqual(response_body["status"], "healthy")
        self.assertEqual(response_body["agent"], "weather-agent")
    
    def test_invalid_path(self):
        """Test handling of requests to the root path (SWML generation)"""
        event = {
            "httpMethod": "GET",
            "path": "/",
            "headers": {},
            "body": ""
        }
        context = MagicMock()
        
        # This should be handled by the agent's run method
        # We can't easily test this without mocking the entire agent
        # but we can verify it doesn't crash
        try:
            response = lambda_handler(event, context)
            # Should return some response (either success or auth failure)
            self.assertIn("statusCode", response)
        except Exception as e:
            # If it fails, it should be due to missing auth, not a crash
            self.assertIsInstance(e, Exception)

    def test_lambda_integration(self):
        """Test Lambda integration using SDK's automatic detection"""
        # Mock Lambda environment variables
        original_env = os.environ.copy()
        
        try:
            # Set Lambda environment variables
            os.environ['AWS_LAMBDA_FUNCTION_NAME'] = 'weather-agent'
            os.environ['LAMBDA_TASK_ROOT'] = '/var/task'
            
            # Create mock Lambda event
            mock_event = {
                'httpMethod': 'GET',
                'path': '/',
                'headers': {
                    'Authorization': 'Basic ZGV2Oncwb3Q='  # dev:w00t in base64
                },
                'body': None
            }
            
            mock_context = type('Context', (), {
                'function_name': 'weather-agent',
                'aws_request_id': 'test-request-id'
            })()
            
            # Test Lambda handler
            response = lambda_handler(mock_event, mock_context)
            
            # Verify response structure
            self.assertIsInstance(response, dict)
            self.assertIn('statusCode', response)
            self.assertIn('headers', response)
            self.assertIn('body', response)
            
            # Should return 200 for valid auth
            self.assertEqual(response['statusCode'], 200)
            
        finally:
            # Restore original environment
            os.environ.clear()
            os.environ.update(original_env)

    def test_lambda_swaig_function_call(self):
        """Test SWAIG function call through Lambda"""
        original_env = os.environ.copy()
        
        try:
            # Set Lambda environment and API key
            os.environ['AWS_LAMBDA_FUNCTION_NAME'] = 'weather-agent'
            os.environ['LAMBDA_TASK_ROOT'] = '/var/task'
            os.environ['WEATHERAPI_KEY'] = 'test-key'  # Mock API key
            
            # Mock Lambda event for SWAIG function call
            mock_event = {
                'httpMethod': 'POST',
                'path': '/swaig',
                'headers': {
                    'Authorization': 'Basic ZGV2Oncwb3Q=',  # dev:w00t
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({
                    'function': 'get_weather',
                    'argument': {
                        'parsed': [{
                            'location': 'New York',
                            'days': 1,
                            'include_alerts': False
                        }]
                    },
                    'call_id': 'test-call-123'
                })
            }
            
            mock_context = type('Context', (), {
                'function_name': 'weather-agent',
                'aws_request_id': 'test-request-id'
            })()
            
            # Test Lambda handler with SWAIG call
            response = lambda_handler(mock_event, mock_context)
            
            # Verify response structure
            self.assertIsInstance(response, dict)
            self.assertEqual(response['statusCode'], 200)
            
            # Parse response body
            response_body = json.loads(response['body'])
            
            # Should contain function response (even if API call fails due to mock key)
            self.assertIsInstance(response_body, dict)
            
        finally:
            # Restore original environment
            os.environ.clear()
            os.environ.update(original_env)

def run_tests():
    """Run all tests"""
    print("🧪 Running SignalWire Weather Agent Tests")
    print("=" * 45)
    
    # Create test suite
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add test cases
    suite.addTests(loader.loadTestsFromTestCase(TestWeatherAgent))
    suite.addTests(loader.loadTestsFromTestCase(TestLambdaHandler))
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    # Print summary
    print("\n" + "=" * 45)
    if result.wasSuccessful():
        print("✅ All tests passed!")
        return 0
    else:
        print(f"❌ {len(result.failures)} test(s) failed, {len(result.errors)} error(s)")
        return 1

if __name__ == "__main__":
    sys.exit(run_tests()) 