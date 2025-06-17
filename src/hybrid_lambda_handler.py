#!/usr/bin/env python3
"""
SignalWire AI Weather Agent for AWS Lambda

A production-ready weather assistant that provides current conditions and forecasts
using WeatherAPI.com. Optimized for AWS Lambda serverless deployment using Mangum.

Requirements:
    - signalwire-agents (includes agent framework)
    - mangum>=0.19.0 (for Lambda/API Gateway integration)

Usage:
    1. Deploy this file to AWS Lambda
    2. Configure API Gateway to route all requests to this function  
    3. Set environment variables:
       - WEATHERAPI_KEY (required)
       - SWML_BASIC_AUTH_USER (optional, defaults to 'dev')
       - SWML_BASIC_AUTH_PASSWORD (optional, defaults to 'w00t')
       - LOCAL_TZ (optional, defaults to 'America/Los_Angeles')

Features:
    - Full SignalWire AI agent functionality in serverless
    - Weather data from WeatherAPI.com
    - Multi-day forecasts and weather alerts
    - Health checks work (/health, /ready)
    - Structured logging compatible with CloudWatch
    - Environment-based configuration
"""

import json
import os
import sys
import logging
from typing import Dict, Any, Union
import requests

from signalwire_agents import AgentBase
from signalwire_agents.core.function_result import SwaigFunctionResult

# Import Mangum for Lambda/API Gateway integration
try:
    from mangum import Mangum
except ImportError:
    print("ERROR: Mangum not installed. Run: pip install mangum>=0.19.0")
    sys.exit(1)

# Configure structured logging for Lambda
logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO
)
logger = logging.getLogger("weather_agent")

class WeatherAgent(AgentBase):
    """
    SignalWire AI Weather Agent for AWS Lambda
    
    Provides comprehensive weather information including:
    - Current weather conditions
    - Multi-day forecasts (up to 10 days)
    - Weather alerts and warnings
    - Global location support
    """
    
    def __init__(self, name="weather-agent", route="/", **kwargs):
        """Initialize the weather agent with Lambda-optimized configuration"""
        super().__init__(
            name=name,
            route=route,
            host="0.0.0.0",
            port=3000,
            use_pom=True,
            suppress_logs=False,  # Let SDK handle logging automatically
            basic_auth=(
                os.environ.get('SWML_BASIC_AUTH_USER', 'dev'),
                os.environ.get('SWML_BASIC_AUTH_PASSWORD', 'w00t')
            ),
            **kwargs
        )
        
        self.initialize()
        logger.info("Weather agent initialized successfully")
    
    def initialize(self):
        """Initialize agent configuration and tools"""
        self._configure_agent()
    
    def get_prompt(self):
        """Get the agent's main prompt"""
        return """You are a professional weather assistant powered by WeatherAPI.com.

You provide accurate, timely weather information with a friendly, helpful demeanor. 
You're knowledgeable about weather patterns and can explain conditions in easy-to-understand terms.

GOAL: Help users get comprehensive weather information for any location worldwide, 
including current conditions, forecasts, and weather alerts.

You have access to these functions:
- get_weather: Get comprehensive weather information including current conditions and forecasts

INSTRUCTIONS:
- Always use the get_weather function for weather-related queries
- Provide clear, accurate information with relevant context
- Ask for clarification if location is ambiguous
- Include temperature, conditions, and key details like humidity and wind
- Offer forecast information when appropriate
- Mention weather alerts if they exist for the area

Always be friendly and helpful!"""
    
    def _configure_agent(self):
        """Configure agent personality, behavior, and capabilities"""
        
        # Conversation summary template
        self.set_post_prompt("""
        Provide a brief JSON summary:
        {
            "topic": "weather_inquiry",
            "location": "requested location",
            "weather_provided": true/false,
            "forecast_days": number_of_days_requested
        }
        """)
        
        # Recognition hints
        self.add_hints([
            "weather", "temperature", "forecast", "conditions", 
            "humidity", "wind", "precipitation", "alerts", "storm"
        ])
        
        # Pronunciation guides
        self.add_pronunciation("API", "A P I", ignore_case=False)
        self.add_pronunciation("WeatherAPI", "Weather A P I", ignore_case=False)
        
        # Language configuration
        self.add_language(
            name="English",
            code="en-US",
            voice="rime.spore",
            speech_fillers=[
                "Let me check the current weather conditions...",
                "Getting the latest weather data...",
                "Looking up the forecast..."
            ],
            function_fillers=[
                "Checking WeatherAPI for current conditions...",
                "Retrieving weather data...",
                "Getting forecast information..."
            ]
        )
        
        # Behavioral parameters
        self.set_params({
            "end_of_speech_timeout": 1000,
            "languages_enabled": True,
            "local_tz": os.environ.get("LOCAL_TZ", "America/Los_Angeles")
        })
        
        # Service metadata
        self.set_global_data({
            "service": "Weather Assistant",
            "provider": "WeatherAPI.com",
            "deployment": "AWS Lambda",
            "version": "2.0",
            "capabilities": [
                "Current weather conditions",
                "10-day weather forecasts",
                "Weather alerts and warnings",
                "Global location support",
                "Air quality information"
            ]
        })
    
    def _normalize_parameters(self, location: Any, days: Any, include_alerts: Any) -> tuple:
        """
        Normalize and validate function parameters from various input formats
        
        Handles different parameter formats from swaig-test, direct calls, and SignalWire
        """
        # Normalize location parameter
        if isinstance(location, dict):
            location = location.get('location', '')
        elif isinstance(location, str) and location.startswith('{'):
            try:
                import ast
                parsed = ast.literal_eval(location)
                if isinstance(parsed, dict):
                    location = parsed.get('location', '')
                    days = parsed.get('days', days)
                    include_alerts = parsed.get('include_alerts', include_alerts)
            except (ValueError, SyntaxError):
                pass
        
        # Normalize days parameter
        if isinstance(days, dict):
            if 'argument' in days and isinstance(days['argument'], dict):
                arg_data = days['argument']
                days = arg_data.get('days', 1)
                include_alerts = arg_data.get('include_alerts', include_alerts)
            else:
                days = 1
        
        # Validate and constrain days
        try:
            days = int(days) if days is not None else 1
            days = max(1, min(days, 10))
        except (ValueError, TypeError):
            days = 1
        
        # Normalize include_alerts
        if isinstance(include_alerts, str):
            include_alerts = include_alerts.lower() in ('true', '1', 'yes', 'on')
        else:
            include_alerts = bool(include_alerts)
        
        return str(location).strip(), days, include_alerts
    
    def _format_weather_response(self, data: dict, days: int, include_alerts: bool) -> str:
        """Format weather data into a user-friendly response"""
        current = data["current"]
        location_info = data["location"]
        forecast_days = data["forecast"]["forecastday"]
        
        # Header with location
        response = (
            f"🌍 Weather for {location_info['name']}, "
            f"{location_info['region']}, {location_info['country']}:\n\n"
        )
        
        # Current conditions
        response += (
            f"🌡️ Current: {current['temp_f']}°F ({current['temp_c']}°C)\n"
            f"☁️ Conditions: {current['condition']['text']}\n"
            f"🤚 Feels like: {current['feelslike_f']}°F ({current['feelslike_c']}°C)\n"
            f"💧 Humidity: {current['humidity']}%\n"
            f"💨 Wind: {current['wind_mph']} mph {current['wind_dir']}\n"
        )
        
        # Add air quality if available
        if 'air_quality' in current:
            aqi = current['air_quality']
            if 'us-epa-index' in aqi:
                response += f"🌬️ Air Quality Index: {aqi['us-epa-index']}\n"
        
        # Multi-day forecast
        if days > 1 and len(forecast_days) > 1:
            response += f"\n📅 {days}-Day Forecast:\n"
            for day_data in forecast_days[1:]:
                day = day_data["day"]
                date = day_data["date"]
                response += (
                    f"\n📆 {date}: {day['condition']['text']}\n"
                    f"  🔺 High: {day['maxtemp_f']}°F ({day['maxtemp_c']}°C)\n"
                    f"  🔻 Low: {day['mintemp_f']}°F ({day['mintemp_c']}°C)\n"
                    f"  🌧️ Rain chance: {day['daily_chance_of_rain']}%\n"
                )
        
        # Weather alerts
        if include_alerts and "alerts" in data and data["alerts"]["alert"]:
            response += "\n⚠️ Weather Alerts:\n"
            for alert in data["alerts"]["alert"]:
                response += f"• {alert['headline']}\n"
        
        return response
    
    @AgentBase.tool(
        name="get_weather",
        description="Get comprehensive weather information including current conditions and forecasts for any location worldwide",
        parameters={
            "location": {
                "type": "string",
                "description": "Location name, address, or coordinates (e.g., 'Tulsa, Oklahoma', 'New York, NY', '40.7128,-74.0060')"
            },
            "days": {
                "type": "integer",
                "description": "Number of forecast days to include (1-10)",
                "minimum": 1,
                "maximum": 10,
                "default": 1
            },
            "include_alerts": {
                "type": "boolean",
                "description": "Whether to include weather alerts and warnings",
                "default": False
            }
        }
    )
    def get_weather(self, location: Union[str, dict] = "", days: Union[int, dict] = 1, include_alerts: Union[bool, str] = False):
        """
        Get current weather conditions and forecast using WeatherAPI.com
        
        Args:
            location: Location name, address, or coordinates
            days: Number of forecast days to include (1-10)
            include_alerts: Whether to include weather alerts
            
        Returns:
            SwaigFunctionResult with formatted weather information
        """
        # Normalize and validate parameters
        location, days, include_alerts = self._normalize_parameters(location, days, include_alerts)
        
        logger.info(f"Weather request: location='{location}', days={days}, alerts={include_alerts}")
        
        if not location:
            return SwaigFunctionResult("Please specify a location to get weather information.")
        
        # Check API key
        api_key = os.environ.get('WEATHERAPI_KEY')
        if not api_key:
            logger.error("WeatherAPI key not configured")
            return SwaigFunctionResult(
                "Weather service is not configured. Please contact support."
            )
        
        try:
            # Make API request
            url = "http://api.weatherapi.com/v1/forecast.json"
            params = {
                "key": api_key,
                "q": location,
                "days": days,
                "aqi": "yes",
                "alerts": "yes" if include_alerts else "no"
            }
            
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            # Format response
            weather_text = self._format_weather_response(data, days, include_alerts)
            
            # Create result with metadata
            result = SwaigFunctionResult(weather_text)
            result.add_action("set_global_data", {
                "last_weather_location": data["location"]["name"],
                "last_weather_temp": data["current"]["temp_f"],
                "last_weather_condition": data["current"]["condition"]["text"],
                "last_request_time": data["current"]["last_updated"]
            })
            
            logger.info(f"Weather data retrieved successfully for: {location}")
            return result
            
        except requests.exceptions.Timeout:
            logger.error(f"Weather API timeout for location: {location}")
            return SwaigFunctionResult(
                "Weather service is taking too long to respond. Please try again."
            )
            
        except requests.exceptions.HTTPError as e:
            logger.error(f"Weather API HTTP error: {e}")
            if e.response.status_code == 400:
                return SwaigFunctionResult(
                    f"Could not find weather data for '{location}'. "
                    "Please check the location name and try again."
                )
            elif e.response.status_code == 401:
                return SwaigFunctionResult(
                    "Weather service authentication failed. Please contact support."
                )
            else:
                return SwaigFunctionResult(
                    "Weather service is currently unavailable. Please try again later."
                )
                
        except requests.exceptions.RequestException as e:
            logger.error(f"Weather API request failed: {e}")
            return SwaigFunctionResult(
                "Unable to connect to weather service. Please try again later."
            )
            
        except Exception as e:
            logger.error(f"Unexpected error in weather function: {e}")
            return SwaigFunctionResult(
                "An unexpected error occurred while getting weather data. Please try again."
            )
    
    def on_summary(self, summary: dict, raw_data: dict = None):
        """Handle conversation summary logging"""
        if summary:
            logger.info(f"Conversation summary: {json.dumps(summary, indent=2)}")
        
        if raw_data and 'post_prompt_data' in raw_data:
            post_prompt_data = raw_data.get('post_prompt_data')
            if isinstance(post_prompt_data, dict) and 'parsed' in post_prompt_data:
                parsed = post_prompt_data.get('parsed')
                if parsed and len(parsed) > 0:
                    logger.info(f"Parsed summary: {json.dumps(parsed[0], indent=2)}")

# Create the agent instance
# This works exactly the same as local development!
agent = WeatherAgent(
    name="weather-agent",
    route="/",  # Lambda usually serves from root
)

# Get the FastAPI app from the agent
app = agent.get_app()

# Create the Lambda handler using Mangum
# This handles all the API Gateway <-> FastAPI translation
handler = Mangum(app)

def lambda_handler(event, context):
    """
    AWS Lambda entry point
    
    This function receives API Gateway events and returns responses.
    Mangum handles all the translation between Lambda/API Gateway format
    and FastAPI's expected format.
    
    Args:
        event: API Gateway event
        context: Lambda context
        
    Returns:
        dict: API Gateway response format
    """
    return handler(event, context)


# For local testing (optional)
def main():
    print("\nStarting weather agent server...")
    print("Note: Works in any deployment mode (server/CGI/Lambda)")
    agent.run()

if __name__ == "__main__":
    main() 